// Stereo to mono transform stream

import * as stream from "stream";

export default class StereoToMono extends stream.Transform {
    override _transform(chunk, enc, cb) {
        // LLRRLLRR    LLLL
        // 01234567 -> 0145
        const buf = Buffer.alloc(chunk.length / 2);
        for(var i = 0; i < chunk.length / 2; i++) {
            buf[i * 2] = chunk[i * 4];
            buf[i * 2 + 1] = chunk[i * 4 + 1];
        }
        this.push(buf);
        cb();
    }
}
