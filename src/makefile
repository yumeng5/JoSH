CC = gcc
#Using -Ofast instead of -O3 might result in faster code, but is supported only by newer GCC versions
CFLAGS = -lm -pthread -O3 -march=native -Wall -funroll-loops -Wno-unused-result

all: josh

josh : josh.c
	$(CC) josh.c -o josh $(CFLAGS)

clean:
	rm -rf josh
	