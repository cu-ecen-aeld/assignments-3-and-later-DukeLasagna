#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslog.h>
#include <errno.h>

int main(int argc, char *argv[]) {

    /* syslog setup */
    openlog(NULL, LOG_CONS, LOG_USER);

    if (argc != 3) {
        syslog(LOG_ERR, "Error: requires writefile and writestr arguments");
        exit(1);
    }

    char *writefile = argv[1];
    char *writestr = argv[2];
    int fd; // file descriptor
    ssize_t nr;

    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    fd = creat(writefile, 0644);
    if (fd == -1) {
        syslog(LOG_ERR, "Error: could not create %s: %s", writefile, strerror(errno));
        exit(1);
    }

    nr = write(fd, writestr, strlen(writestr));
    if (nr == -1) {
        syslog(LOG_ERR, "Error: could not write to %s: %s", writefile, strerror(errno));
        exit(1);
    }

    if (close(fd) == -1) {
        syslog(LOG_ERR, "Error: could not close %s: %s", writefile, strerror(errno));
        exit(1);
    }

    syslog(LOG_DEBUG, "Success");
    closelog();
    return 0;
}
