# jog.mod for ../sdl
module sdl
version 0.2.1
kind library
jog 0.0.1

require mathx ../vendor/mathx-1.2.0.jogz

export video
export events

link.windows SDL3
link.linux SDL3
link.macos SDL3
