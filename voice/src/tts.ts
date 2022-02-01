// Text-to-speech thing

import got from "got";
import * as fs from "fs";

export default function say(text: string, lang: string, path: string, cb: () => any) {
    const voices = {
        "en": "Amazon US English (Justin)",
        "ru": "Amazon Russian (Tatyana)"
    }
    // POST createParts
    got.post("https://support.readaloud.app/ttstool/createParts", {
        json: [
            {
                ssml: `<speak version="1.0" xml:lang="en-US">
                           <prosody volume='default' rate='slow' pitch='default'>
                               ${text}
                           </prosody>
                       </speak>`,
                voiceId: voices[lang]
            }
        ],
        headers: {
            "user-agent": "Mozilla/5.0 (X11; Linux x86_64; rv:96.0) Gecko/20100101 Firefox/96.0",
            "accept": "*/*"
        }
    }).then((response) => {
        const [id] = JSON.parse(response.body);
        // GET audio
        return got(`https://support.readaloud.app/ttstool/getParts?q=${id}`, {
            headers: {
                "user-agent": "Mozilla/5.0 (X11; Linux x86_64; rv:96.0) Gecko/20100101 Firefox/96.0",
                "accept": "audio/*",
                "range": "bytes=0-"
            }
        });
    }).then((response) => {
        fs.writeFile(path, response.rawBody, cb);
    });
}