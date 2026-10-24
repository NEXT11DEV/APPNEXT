#include "ForgeSignBridge.h"
#include <cstdio>
#include <cstring>
int main(int argc, char** argv) {
    if (argc != 7) return 90;
    char message[2048] = {}, bid[512] = {}, version[128] = {};
    int status = forgesign_sign_ipa(argv[1], argv[2], argv[3], argv[4], nullptr, nullptr, nullptr,
        nullptr, argv[5], argv[6], 0, 0, message, sizeof(message), bid, sizeof(bid), version, sizeof(version));
    printf("status=%d message=%s bundle=%s version=%s\n", status, message, bid, version);
    return status;
}

