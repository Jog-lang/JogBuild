# a module that names the operating systems it implements
module demo
version 0.1.0
kind library
jog 0.0.1

targets windows linux macos wasm

export video

link m
link.windows ws2_32
