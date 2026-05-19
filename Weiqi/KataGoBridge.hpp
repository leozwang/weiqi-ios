#pragma once

#include <string>

class KataGoBridge {
public:
    KataGoBridge();
    ~KataGoBridge();

    int initEngine(const std::string& configPath, const std::string& modelPath);
    std::string sendGtpCommand(const std::string& command);
    void shutdown();
};
