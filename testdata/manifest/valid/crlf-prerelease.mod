# CRLF line endings, tabs between words, and a prerelease version.
module	demo
version 1.0.0-rc.1
kind library # trailing comment
jog 0.0.1

require util ./vendor/util
require win C:/libs/win
export tools.extra
