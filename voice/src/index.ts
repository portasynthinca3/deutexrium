import * as path from "path";
import * as fs from "fs";
import { EventEmitter } from "events";

import * as gtts from "gtts";
import * as vosk from "vosk";
import * as prism from "prism-media";
import S2M from "./s2m";
import * as md5 from "md5";
import * as ws from "ws";
import { nanoid } from "nanoid";

import * as voice from "@discordjs/voice";
import * as discord from "discord.js";

const models = {};
const client = new discord.Client({
    intents: [
        discord.Intents.FLAGS.GUILDS,
        discord.Intents.FLAGS.GUILD_VOICE_STATES,
    ]
});

function loadModel(lang: string) {
    models[lang] = new vosk.Model(`${process.argv[1]}/models/${lang}`);
}

type Alternatives = { confidence: number, text: string }[];

class Connection extends EventEmitter {
    channel: discord.VoiceChannel;
    connection: voice.VoiceConnection;
    lang: string;

    constructor(channel: discord.VoiceChannel, lang: string) {
        super();
        // save things and create connection
        this.lang = lang;
        this.channel = channel;
        this.connection = voice.joinVoiceChannel({
            channelId: channel.id,
            guildId: channel.guild.id,
            adapterCreator: channel.guild.voiceAdapterCreator,
            selfDeaf: false,
            selfMute: false
        });

        this.connection.on(voice.VoiceConnectionStatus.Disconnected, () => {
            this.emit("disconnected");
        });

        // start receiving when ready
        this.connection.on(voice.VoiceConnectionStatus.Ready, () => {
            const receiver = this.connection.receiver;
            // when somebody starts talking
            receiver.speaking.on("start", (user) => {
                const stream = receiver.subscribe(user, {
                    end: {
                        behavior: voice.EndBehaviorType.AfterSilence,
                        duration: 1000
                    }
                });

                // decode opus stream and recognize their speech
                const decoder = new prism.opus.Decoder({ channels: 2, rate: 48000, frameSize: 960 });
                const rec = new vosk.Recognizer({ model: models[lang], sampleRate: 48000 });
                rec.setMaxAlternatives(10);
                stream.pipe(decoder).pipe(new S2M()).on("data", (chunk) => {
                    rec.acceptWaveform(chunk);
                }).on("end", () => {
                    let { alternatives } = rec.finalResult() as { alternatives: Alternatives };
                    alternatives = alternatives.map((a) => ({ ...a, text: a.text.trim() })); // trim
                    const text = alternatives.reduce((a, b) => a.confidence > b.confidence ? a : b).text;
                    this.emit("recognized", { user, result: { text, alternatives } });
                    rec.free();
                });
            });
        });
    }

    destroy() {
        this.connection.destroy();
    }

    say(text: string) {
        if(!text) return;

        const path = `/tmp/${nanoid(10)}.mp3`;
        // call gtts
        new gtts(text, this.lang).save(path, (err) => {
            if(err) return;
            if(!fs.existsSync(path)) return;

            const player = voice.createAudioPlayer();
            player.play(voice.createAudioResource(path));
            this.connection.subscribe(player);

            // remove audio file after playing it
            player.on(voice.AudioPlayerStatus.Idle, () => {
                fs.rmSync(path);
            });
        });
    }
}

client.on("ready", () => {
    console.log(`Logged in as ${client.user.tag}`);

    const server = new ws.Server({ port: parseInt(process.env.PORT ?? "2700") });
    server.on("connection", (socket) => {
        console.log("Got connection");
        let conn: Connection = null;

        socket.on("message", (msg) => {
            const data = JSON.parse(msg.toString());
            if(data.op === "connect") {
                // connect to voice channel
                const chan = client.channels.cache.find(x => x.id === data.id) as discord.VoiceChannel;
                conn = new Connection(chan, data.lang);
                conn.on("recognized", ({ user, result }) => {
                    // send event when something got said
                    socket.send(JSON.stringify({
                        op: "recognized",
                        user, result
                    }));
                }).on("disconnected", () => {
                    socket.send(JSON.stringify({
                        op: "disconnected"
                    }));
                    socket.close();
                });
            } else if(data.op === "say") {
                // say something in vc
                conn.say(data.text);
            } else if(data.op === "disconnect") {
                // disconnect from vc
                if(conn) conn.destroy();
            }
        }).on("close", () => {
            if(conn) conn.destroy();
            console.log("Connection closed");
        });
    });
});

loadModel("en");
loadModel("ru");
client.login(process.env.DEUTEX_TOKEN);
