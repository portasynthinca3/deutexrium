import gtts = require("gtts");
import vosk = require("vosk");
import path = require("path");

new gtts("hello world", "en").save(path.join(__dirname, "test.mp3"), () =>
    console.log("saved!"));
