CC ?= gcc
CFLAGS = -Wall -Werror

all: aesdsocket

aesdsocket: aesdsocket.c
	rm -f /var/tmp/aesdsocketdata testfile.sh.log
	$(CC) $(CFLAGS) aesdsocket.c -o aesdsocket

clean:
	rm -f aesdsocket
