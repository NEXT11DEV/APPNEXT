#include "ForgeSignBridge.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <fstream>
#include <sys/stat.h>
int main(int argc, char** argv) {
    if (argc != 7 && argc != 8) return 90;
    char message[2048] = {}, bid[512] = {}, version[128] = {};
    std::string mode = argc == 8 ? argv[7] : "legacy";
    std::string prepared = std::string(argv[6]) + "/taif_prepared";
    int status;
    if (mode != "legacy") {
        char json[32768] = {};
        status = forgesign_prepare_ipa(argv[1], argv[6], json, sizeof(json), message, sizeof(message));
        if (status) { printf("prepare=%d message=%s\n", status, message); return status; }
        if (mode == "stale") { std::ofstream f(argv[1], std::ios::app | std::ios::binary); f << 'x'; }
        if (mode == "outside") prepared = argv[6];
        if (mode == "prepared") {
            // This resource exists only in the prepared tree. Its signed output
            // proves that the signer used that tree instead of extracting again.
            std::ofstream proof(prepared + "/Payload/Smoke.app/prepared-proof.txt");
            proof << "prepared tree was reused";
        }
        const char* copiedID = mode == "duplicate" ? "app.taifplus.smokeab" : nullptr;
        const char* copiedName = mode == "duplicate" ? "Smoke ab" : nullptr;
        status = forgesign_sign_prepared_ipa(argv[1], argv[2], argv[3], argv[4], copiedID, copiedName, nullptr,
            nullptr, argv[5], argv[6], 0, 0, message, sizeof(message), bid, sizeof(bid), version, sizeof(version), prepared.c_str());
        if (mode == "prepared" && status == 0) {
            std::string replay = std::string(argv[5]) + ".replay";
            int second = forgesign_sign_prepared_ipa(argv[1], argv[2], argv[3], argv[4], nullptr, nullptr, nullptr,
                nullptr, replay.c_str(), argv[6], 0, 0, message, sizeof(message), bid, sizeof(bid), version, sizeof(version), prepared.c_str());
            if (second == 0) return 91;
        }
    } else {
        status = forgesign_sign_ipa(argv[1], argv[2], argv[3], argv[4], nullptr, nullptr, nullptr,
            nullptr, argv[5], argv[6], 0, 0, message, sizeof(message), bid, sizeof(bid), version, sizeof(version));
    }
    printf("status=%d message=%s bundle=%s version=%s\n", status, message, bid, version);
    return status;
}
