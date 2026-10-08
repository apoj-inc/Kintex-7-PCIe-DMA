#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>
#include <string.h>

#define BUFFER_SIZE 1024

int main (int argc, char **argv) {
    if (argc < 3) {
        return -1;
    }

    char *bdf = malloc(sizeof(strlen(argv[1])));
    if (!bdf) {
        printf("Argv 1 alloc error\n");
        return -1;
    }
    if (!strcpy(bdf, argv[1])) {
        printf("Argv 1 strcpy error\n");
        return -1;
    }
    int channel = atoi(argv[2]);
    int dma_fd;

    char *filepath;

    int size = asprintf(&filepath, "/dev/hdlnocgen_%s_%d", bdf, channel);
    if (size < 0) {
        printf("Asprintf error\n");
        return size;
    }
    printf("Target file %s\n", filepath);

    dma_fd = open(filepath, O_RDWR);
    free(filepath);
    if (dma_fd < 0) {
        printf("Device or channel does not exist\n");
        return dma_fd;
    }


    char input_str[BUFFER_SIZE];
    char dma_read[BUFFER_SIZE];

    printf("DMA channel %d echodevice demonstration. Write something: ", channel);
    if (!fgets(input_str, sizeof(input_str), stdin)) {
        printf("Failed to read the string\n"); 
        close(dma_fd);
        return -2;
    }

    printf("You entered %s\n", input_str);

    printf("Resetting the DMA controller...\n");


    size = asprintf(&filepath, "/dev/hdlnocgen_%s_dma_csr", bdf);
    if (size < 0) {
        return size;
    }
    printf("Target CSR file %s\n", filepath);

    int csr_fd = open(filepath, O_RDWR);
    free(filepath);
    if (csr_fd < 0) {
        printf("Failed to open CSR file\n");
        return csr_fd;
    }
    uint32_t writedata = 0;
    pwrite(csr_fd, &writedata, 4, (off_t)0xC);
    printf("DMA controller is reset\n");

    printf("Writing to DMA channel %d...\n", channel);
    write(dma_fd, input_str, sizeof(input_str));
    printf("Done\n");
    printf("Reading from DMA channel %d...\n", channel);
    read(dma_fd, dma_read, sizeof(dma_read));
    printf("Done\n");

    printf("DMA says: %s\n", dma_read);

    // Trashing DMA channels
    /*
    printf("Trashing DMA task queue...\n");
    for (int i = 0; i < 8; i++) {
        read(dma_fd, dma_read, sizeof(dma_read));
    }
    printf("Trashing DMA task queue trashed\n");
    */

    close(csr_fd);
    close(dma_fd);
}
