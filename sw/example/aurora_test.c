#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>
#include <string.h>

#define ARRAY_SIZE (uint64_t)(1024*16/8)
#define DMA_CHANNEL_COUNT 8
#define TASK_MULTIPLIER 100

uint64_t kal[DMA_CHANNEL_COUNT*2][TASK_MULTIPLIER][ARRAY_SIZE];
uint64_t checker[DMA_CHANNEL_COUNT*2][TASK_MULTIPLIER][ARRAY_SIZE];
int fd[DMA_CHANNEL_COUNT*2];
int fail[DMA_CHANNEL_COUNT*2];

void *dma_test (void *index) {
    int index_int = (uint64_t)index;
    int addr_offset = 0;
    for (int i = 0; i < TASK_MULTIPLIER; i++) {
        if (index_int < DMA_CHANNEL_COUNT) {
            pwrite(fd[index_int], kal[index_int][i], sizeof(kal[index_int][i]), (off_t)addr_offset);
            pread(fd[index_int+DMA_CHANNEL_COUNT], checker[index_int][i], sizeof(checker[index_int][i]), (off_t)(addr_offset+sizeof(kal[index_int][i])));
        } else {
            pwrite(fd[index_int], kal[index_int][i], sizeof(kal[index_int][i]), (off_t)addr_offset);
            pread(fd[index_int-DMA_CHANNEL_COUNT], checker[index_int][i], sizeof(checker[index_int][i]), (off_t)(addr_offset+sizeof(kal[index_int][i])));
        }
        addr_offset += 0x0;
    }
}

int main (int argc, char **argv) {
    if (argc < 4) {
        return -1;
    }

    char *bdf1 = malloc(sizeof(strlen(argv[1])));
    if (!bdf1) {
        printf("Argv 1 alloc error\n");
        return -1;
    }
    if (!strcpy(bdf1, argv[1])) {
        printf("Argv 1 strcpy error\n");
        return -1;
    }
    char *bdf2 = malloc(sizeof(strlen(argv[2])));
    if (!bdf2) {
        printf("Argv 2 alloc error\n");
        return -1;
    }
    if (!strcpy(bdf2, argv[2])) {
        printf("Argv 2 strcpy error\n");
        return -1;
    }
    int iteration_count = atoi(argv[3]);
    int parallel = atoi(argv[4]);

    pthread_t threads[DMA_CHANNEL_COUNT*2];

    struct timespec start, stop;
    double elapsed = 0;


    for (int i = 0; i < DMA_CHANNEL_COUNT; i++) {
        char *filepath;

        int size = asprintf(&filepath, "/dev/hdlnocgen_%s_%d", bdf1, i);
        if (size < 0) {
            return size;
        }

        fd[i] = open(filepath, O_RDWR);
        free(filepath);
        if (fd[i] < 0) {
            return fd[i];
        }
    }
    for (int i = DMA_CHANNEL_COUNT; i < DMA_CHANNEL_COUNT*2; i++) {
        char *filepath;

        int size = asprintf(&filepath, "/dev/hdlnocgen_%s_%d", bdf2, i-DMA_CHANNEL_COUNT);
        if (size < 0) {
            return size;
        }

        fd[i] = open(filepath, O_RDWR);
        free(filepath);
        if (fd[i] < 0) {
            return fd[i];
        }
    }
    for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
        fail[i] = 0;
    }


    for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
        for (int j = 0; j < TASK_MULTIPLIER; j++) {
            for (int k = 0; k < ARRAY_SIZE; k++) {
                kal[i][j][k] = i * TASK_MULTIPLIER * ARRAY_SIZE + j * ARRAY_SIZE + k;
                checker[i][j][k] = 0;
            }
        }
    }

    char *filepath;
    int size = asprintf(&filepath, "/dev/hdlnocgen_%s_dma_csr", bdf1);
    if (size < 0) {
        return size;
    }
    int csr_fd = open(filepath, O_RDWR);
    free(filepath);
    if (csr_fd < 0) {
        printf("Failed to open CSR file\n");
        return csr_fd;
    }
    uint32_t writedata = 0;
    pwrite(csr_fd, &writedata, 4, (off_t)0xC);
    printf("DMA controller 1 reset\n");

    size = asprintf(&filepath, "/dev/hdlnocgen_%s_dma_csr", bdf2);
    if (size < 0) {
        return size;
    }
    csr_fd = open(filepath, O_RDWR);
    free(filepath);
    if (csr_fd < 0) {
        printf("Failed to open CSR file\n");
        return csr_fd;
    }
    writedata = 0;
    pwrite(csr_fd, &writedata, 4, (off_t)0xC);
    printf("DMA controller 2 reset\n");

    for (int iter = 0; iter < iteration_count; iter++) {
        
        clock_gettime(CLOCK_MONOTONIC, &start);
        for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
            pthread_create(&threads[i], NULL, dma_test, (void *)(uint64_t)i);
        }
        for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
            pthread_join(threads[i], NULL);
        }
        clock_gettime(CLOCK_MONOTONIC, &stop);

        FILE *log = fopen("log.log", "w+");


        for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
            for (int j = 0; j < TASK_MULTIPLIER; j++) {
                for (int k = 0; k < ARRAY_SIZE; k++) {
                    fprintf(log, "%d %d %d: %lu, %lu", i, j, k, kal[i][j][k], checker[i][j][k]);
                    if (kal[i][j][k] != checker[i][j][k]) {
                        fail[i]++;
                        fprintf(log, " FAIL!!!");
                    }
                    fprintf(log, "\n");
                }
            }
        }
        for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
            for (int j = 0; j < TASK_MULTIPLIER; j++) {
                for (int k = 0; k < ARRAY_SIZE; k++) {
                    checker[i][j][k] = 0;
                }
            }
        }

        elapsed += (stop.tv_sec*1e9 + stop.tv_nsec) - (start.tv_sec*1e9 + start.tv_nsec);
    }
    printf("All channels read from dma\n");

    printf("Fail array: ");
    for (int i = 0; i < DMA_CHANNEL_COUNT*2; i++) {
        printf("%d ", fail[i]);
    }
    printf("\n");

    uint64_t bitcount = (sizeof(kal) + sizeof(checker))*8*iteration_count;
    printf("Speed: %lf Gbit/sec\n", bitcount/elapsed);
}
