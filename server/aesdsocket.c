#include <arpa/inet.h>
#include <asm-generic/socket.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>

#define PORT "9000"
#define BUFFER_SIZE 1024
#define LOG_FILE "/var/tmp/aesdsocketdata"

// Global variable to track if a SIGINT or SIGTERM was received
volatile sig_atomic_t keep_running = 1;

int fd, server_fd;

// Function to handle SIGINT and SIGTERM
void signal_handler(int sig) {
    keep_running = 0;
    shutdown(server_fd, SHUT_RDWR);
    remove(LOG_FILE);
    closelog();

    exit(EXIT_SUCCESS);
}

static void exit_failure(void) {
    close(fd);
    closelog();

    exit(EXIT_FAILURE);
}

// Main function
int main(int argc, char *argv[]) {
    char buffer[BUFFER_SIZE] = {0};
    int opt = 1;
    int daemon_mode = 0;

    // Check if -d argument is provided for daemon mode
    if (argc >= 2 && strcmp(argv[1], "-d") == 0) {
        daemon_mode = 1;
    }

    // Logging setup
    openlog("aesdsocket", LOG_PID, LOG_USER);

    // Signal handling for graceful shutdown
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    struct addrinfo hints;
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = AI_PASSIVE;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = 0;

    struct addrinfo *res;
    int ret_getaddr = getaddrinfo(NULL, PORT, &hints, &res);
    if (ret_getaddr != 0) {
        syslog(LOG_ERR, "Error get address info: %i\n", ret_getaddr);
        exit_failure();
    }

    server_fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (server_fd == (-1)) {
        syslog(LOG_ERR, "Error open socket: %s\n", strerror(errno));
        exit_failure();
    }
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    int ret_bind = bind(server_fd, res->ai_addr, res->ai_addrlen);
    if (ret_bind == (-1)) {
        syslog(LOG_ERR, "Error bind address: %s\n", strerror(errno));
        exit_failure();
    }
    syslog(LOG_DEBUG, "Bind address success: %i\n", ret_bind);
    freeaddrinfo(res);

    // Enter daemon mode if -d is specified
    if (daemon_mode) {
        pid_t pid = fork();
        if (pid < 0) {
            exit(EXIT_FAILURE);
        }
        if (pid > 0) {
            exit(EXIT_SUCCESS); // Parent exits
        }
        // Child (daemon) continues
    }

    int ret_listen = listen(server_fd, 10);
    if (ret_listen == (-1)) {
        syslog(LOG_ERR, "Error listen: %s\n", strerror(errno));
        exit_failure();
    }
    syslog(LOG_DEBUG, "Listen success\n");

    int new_socket = 0;
    struct sockaddr incoming_addr;
    socklen_t incoming_addr_len = 0;

    // Main loop to accept connections
    while (true) {
        if ((new_socket = accept(server_fd, &incoming_addr, &incoming_addr_len)) < 0) {
            perror("accept");
            continue;
        }

        // Handle connection...
        ssize_t num_bytes;

        // Open or create file where data will be stored
        fd = open(LOG_FILE, O_CREAT | O_APPEND | O_RDWR, S_IRWXU | S_IRGRP | S_IROTH);
        if (fd == (-1)) {
            perror("File open error");
            exit_failure();
        }

        bool packet_complete = false;
        do {
            memset(buffer, 0, BUFFER_SIZE);
            num_bytes = recv(new_socket, buffer, BUFFER_SIZE - 1, 0);
            if (num_bytes == -1) {
                exit_failure();
            }

            if (strchr(buffer, '\n') != NULL) {
                packet_complete = true;
                syslog(LOG_DEBUG, "Received completed\n");
            }

            // Append received data to the file
            int number_of_bytes_write;
            number_of_bytes_write = write(fd, buffer, num_bytes);
            if (number_of_bytes_write == (-1)) {
                syslog(LOG_ERR, "Error writing rx file: %s\n", strerror(errno));
                exit_failure();
            }
            syslog(LOG_USER, "Save data: %s", buffer);

        } while (packet_complete == false); // Check for newline

        packet_complete = false;
        lseek(fd, 0, SEEK_SET);
        do {
            num_bytes = read(fd, buffer, BUFFER_SIZE);
            if (num_bytes == (-1)) {
                syslog(LOG_ERR, "Error reading rx file: %s\n", strerror(errno));
                exit_failure();
            }
            syslog(LOG_DEBUG, "Read %li bytes success\n", num_bytes);

            if (num_bytes == 0) {
                packet_complete = true;
                syslog(LOG_DEBUG, "Read completed\n");
            } else {
                num_bytes = send(new_socket, buffer, num_bytes, 0);
                if (num_bytes == (-1)) {
                    syslog(LOG_ERR, "Error sending: %s\n", strerror(errno));
                    exit_failure();
                }
                syslog(LOG_DEBUG, "Send %li bytes success\n", num_bytes);
            }
        } while (packet_complete == false);

        close(fd);
    }

    // Cleanup
    if (server_fd > 0) {
        close(server_fd);
        remove("/var/tmp/aesdsocketdata");
        close(new_socket);
    }

    // Remove the data file

    // Close syslog
    closelog();

    syslog(LOG_USER, "Shutdown complete");

    return 0;
}
