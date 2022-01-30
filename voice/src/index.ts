import * as path from "path";
import * as fs from "fs";

import * as gtts from "gtts";
import * as vosk from "vosk";
import * as prism from "prism-media";
import S2M from "./s2m";
import * as md5 from "md5";

import * as voice from "@discordjs/voice";
import * as discord from "discord.js";

const model = new vosk.Model("./models/en");
const client = new discord.Client({
    intents: [
        discord.Intents.FLAGS.GUILDS,
        discord.Intents.FLAGS.GUILD_VOICE_STATES,
    ]
});

type RecCallback = (user: string, text: string) => any;

class Connection {
    channel: discord.VoiceChannel;
    connection: voice.VoiceConnection;
    recognized: RecCallback;

    constructor(channel: discord.VoiceChannel, recognized: RecCallback) {
        // save things and create connection
        this.recognized = recognized;
        this.channel = channel;
        this.connection = voice.joinVoiceChannel({
            channelId: channel.id,
            guildId: channel.guild.id,
            adapterCreator: channel.guild.voiceAdapterCreator,
            selfDeaf: false,
            selfMute: false
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
                const rec = new vosk.Recognizer({ model, sampleRate: 48000 });
                stream.pipe(decoder).pipe(new S2M()).on("data", (chunk) => {
                    rec.acceptWaveform(chunk);
                }).on("end", () => {
                    this.recognized(user, rec.result().text);
                    rec.free();
                });
            });
        });
    }

    destroy() {
        this.connection.destroy();
    }

    say(text: string) {
        const path = `/tmp/${md5(text)}.mp3`;
        // call gtts
        new gtts(text, "en").save(path, () => {
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
});

client.login(process.env.DEUTEX_TOKEN);
