CROSS_COMPILE=
srcs = writer.c
objs = $(srcs:.c=.o)

.PHONY: all
all: writer

.PHONY: clean
clean:
	rm -f writer *.o

$(objs): %.o: %.c
	$(CROSS_COMPILE)gcc -c $<

writer: $(objs)
	$(CROSS_COMPILE)gcc -o $@ $?
