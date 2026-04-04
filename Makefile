build:
	odin build .

install:
	sudo cp ./rofi-wifi /usr/local/bin

.PHONY:
	build install
