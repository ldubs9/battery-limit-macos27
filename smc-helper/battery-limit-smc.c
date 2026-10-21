/*
 * Minimal AppleSMC adapter-control helper for Battery Limit.
 *
 * This program intentionally supports one key (CHIE) and two values (00/08).
 * It is installed root-owned and exposed through an exact sudoers allow-list by
 * install.sh. It does not enumerate arbitrary SMC keys or accept arbitrary
 * write payloads.
 *
 * The AppleSMC user-client interface is private and may change between macOS
 * releases. Unsupported machines fail closed with a non-zero exit status.
 */

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9
#define MAX_SMC_BYTES 32

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyDataPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyDataKeyInfo;

typedef struct {
    uint32_t key;
    uint8_t vers[6];
    SMCKeyDataPLimitData pLimitData;
    SMCKeyDataKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[MAX_SMC_BYTES];
} SMCKeyData;

static uint32_t key_code(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) |
           ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) |
           (uint32_t)(uint8_t)key[3];
}

static kern_return_t smc_call(io_connect_t connection,
                              SMCKeyData *input,
                              SMCKeyData *output) {
    size_t input_size = sizeof(*input);
    size_t output_size = sizeof(*output);
    return IOConnectCallStructMethod(connection,
                                     KERNEL_INDEX_SMC,
                                     input,
                                     input_size,
                                     output,
                                     &output_size);
}

static kern_return_t smc_open(io_connect_t *connection) {
    if (!connection) {
        return kIOReturnBadArgument;
    }

    io_service_t service = IOServiceGetMatchingService(
        MACH_PORT_NULL, IOServiceMatching("AppleSMC"));
    if (!service) {
        return kIOReturnNotFound;
    }

    kern_return_t result = IOServiceOpen(
        service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}

static kern_return_t smc_key_info(io_connect_t connection,
                                  uint32_t key,
                                  SMCKeyDataKeyInfo *info) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = smc_call(connection, &input, &output);
    if (result == kIOReturnSuccess && info) {
        *info = output.keyInfo;
    }
    return result;
}

static kern_return_t smc_read_byte(io_connect_t connection,
                                   uint32_t key,
                                   uint8_t *value) {
    if (!value) {
        return kIOReturnBadArgument;
    }

    SMCKeyDataKeyInfo info;
    kern_return_t result = smc_key_info(connection, key, &info);
    if (result != kIOReturnSuccess) {
        return result;
    }
    if (info.dataSize != 1) {
        return kIOReturnBadArgument;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo = info;
    input.data8 = SMC_CMD_READ_BYTES;

    result = smc_call(connection, &input, &output);
    if (result == kIOReturnSuccess) {
        *value = output.bytes[0];
    }
    return result;
}

static kern_return_t smc_write_byte(io_connect_t connection,
                                    uint32_t key,
                                    uint8_t value) {
    SMCKeyDataKeyInfo info;
    kern_return_t result = smc_key_info(connection, key, &info);
    if (result != kIOReturnSuccess) {
        return result;
    }
    if (info.dataSize != 1) {
        return kIOReturnBadArgument;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo = info;
    input.data8 = SMC_CMD_WRITE_BYTES;
    input.bytes[0] = value;
    return smc_call(connection, &input, &output);
}

static void print_usage(const char *program) {
    fprintf(stderr,
            "Usage: %s --key CHIE (--read | --write 00|08)\n",
            program);
}

static int parse_hex_byte(const char *text, uint8_t *value) {
    if (!text || strlen(text) != 2 || !value) {
        return 0;
    }
    char *end = NULL;
    unsigned long parsed = strtoul(text, &end, 16);
    if (!end || *end != '\0' || parsed > 0xff) {
        return 0;
    }
    *value = (uint8_t)parsed;
    return 1;
}

int main(int argc, char **argv) {
    const char *key = NULL;
    int read_requested = 0;
    int write_requested = 0;
    uint8_t write_value = 0;

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--key") == 0 && index + 1 < argc) {
            key = argv[++index];
        } else if (strcmp(argv[index], "--read") == 0) {
            read_requested = 1;
        } else if (strcmp(argv[index], "--write") == 0 && index + 1 < argc) {
            write_requested = parse_hex_byte(argv[++index], &write_value);
            if (!write_requested) {
                fprintf(stderr, "Invalid write value; expected a two-digit hex byte.\n");
                return 2;
            }
        } else {
            print_usage(argv[0]);
            return 2;
        }
    }

    if (!key || strcmp(key, "CHIE") != 0 ||
        (read_requested == write_requested) ||
        (write_requested && write_value != 0x00 && write_value != 0x08)) {
        print_usage(argv[0]);
        return 2;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = smc_open(&connection);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "Unable to open AppleSMC (0x%08x).\n", result);
        return 1;
    }

    uint8_t value = 0;
    if (read_requested) {
        result = smc_read_byte(connection, key_code(key), &value);
    } else {
        result = smc_write_byte(connection, key_code(key), write_value);
    }
    IOServiceClose(connection);

    if (result != kIOReturnSuccess) {
        fprintf(stderr, "AppleSMC operation failed (0x%08x).\n", result);
        return 1;
    }

    if (read_requested) {
        printf("%02x\n", value);
    }
    return 0;
}
