#include "KataGoBridge.hpp"
#include <vector>
#include <thread>
#include <mutex>
#include <iostream>
#include <sstream>

#include "core/global.h"
#include "core/mainargs.h"
#include "core/config_parser.h"
#include "game/board.h"
#include "search/timecontrols.h"
#include "program/setup.h"
#include "program/gtpconfig.h"
#include "program/playutils.h"
#include "search/asyncbot.h"
#include "program/play.h"
#include "main.h"

namespace {
    std::mutex engineMutex;
    std::unique_ptr<AsyncBot> bot;
    NNEvaluator* g_nnEval = nullptr;
    std::unique_ptr<Logger> logger;
    std::unique_ptr<Rand> seedRand;
    bool initialized = false;

    void oneTimeInit() {
        static std::once_flag flag;
        std::call_once(flag, []() {
            Board::initHash();
            ScoreValue::initTables();
        });
    }

    std::vector<std::string> split(const std::string& s) {
        std::vector<std::string> result;
        std::stringstream ss(s);
        std::string item;
        while (ss >> item) result.push_back(item);
        return result;
    }
}

KataGoBridge::KataGoBridge() {}

KataGoBridge::~KataGoBridge() {
    shutdown();
}

int KataGoBridge::initEngine(const std::string& configPath, const std::string& modelPath) {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (initialized) return 0;

    oneTimeInit();

    try {
        ConfigParser cfg(configPath, true);
        
        // Use the directory containing the config as a base for a 'logs' dir, 
        // but explicitly disable all logging to prevent file creation.
        cfg.overrideKey("logAllGTPCommunication", "false");
        cfg.overrideKey("logSearchInfo", "false");
        cfg.overrideKey("logToStderr", "false");
        cfg.overrideKey("logSearchInfoInterval", "-1");
        cfg.overrideKey("logAllSelfplay", "false");
        cfg.overrideKey("startupPrintMessageToStderr", "false");
        cfg.overrideKey("logSearchInfoForChosenMove", "false");
        
        // Remove the logDir override to /dev/null which was causing errors
        // and instead point it to a subfolder of the model path (which we know is readable/writable-ish)
        std::string internalDir = configPath.substr(0, configPath.find_last_of("/"));
        cfg.overrideKey("logDir", internalDir + "/temp_logs");
        cfg.overrideKey("homeDataDir", internalDir);

        Setup::initializeSession(cfg);
        logger = std::make_unique<Logger>(&cfg);
        seedRand = std::make_unique<Rand>();

        SearchParams params = Setup::loadSingleParams(cfg, Setup::SETUP_FOR_GTP);

        int expectedConcurrentEvals = params.numThreads;
        int defaultMaxBatchSize = std::max(8, ((expectedConcurrentEvals + 3) / 4) * 4);

        std::string expectedSha256 = "";
        g_nnEval = Setup::initializeNNEvaluator(
            modelPath, modelPath, expectedSha256, cfg, *logger, *seedRand, 
            expectedConcurrentEvals, Board::DEFAULT_LEN, Board::DEFAULT_LEN, 
            defaultMaxBatchSize, true, false, Setup::SETUP_FOR_GTP
        );

        Rules rules = Setup::loadSingleRules(cfg, false);

        std::string searchRandSeed = cfg.contains("searchRandSeed") ? cfg.getString("searchRandSeed") : Global::uint64ToString(seedRand->nextUInt64());
        bot = std::make_unique<AsyncBot>(params, g_nnEval, logger.get(), searchRandSeed);
        bot->setAlwaysIncludeOwnerMap(true);

        Board board;
        Player pla = P_BLACK;
        BoardHistory hist(board, pla, rules, 0);
        bot->setPosition(pla, board, hist);

        initialized = true;
    } catch (const std::exception& e) {
        initialized = false;
        return -1;
    } catch (...) {
        initialized = false;
        return -2;
    }

    return 0;
}

std::string KataGoBridge::sendGtpCommand(const std::string& command) {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (!initialized) return "? engine not initialized";

    std::vector<std::string> parts = split(command);
    if (parts.empty()) return "= ";

    std::string mainCmd = parts[0];

    if (mainCmd == "name") return "= KataGo";
    if (mainCmd == "version") return "= " + Version::getKataGoVersion();
    if (mainCmd == "protocol_version") return "= 2";

    if (mainCmd == "genmove") {
        if (parts.size() < 2) return "? missing color";
        std::string colorStr = parts[1];
        Player pla;
        if (colorStr == "black" || colorStr == "b" || colorStr == "B") pla = P_BLACK;
        else if (colorStr == "white" || colorStr == "w" || colorStr == "W") pla = P_WHITE;
        else return "? invalid color";

        TimeControls tc;
        Loc moveLoc = bot->genMoveSynchronous(pla, tc);
        std::string moveStr = Location::toString(moveLoc, bot->getRootBoard());
        bot->makeMove(moveLoc, pla);
        return "= " + moveStr;
    }

    if (mainCmd == "play") {
        if (parts.size() < 3) return "? missing color or move";
        std::string colorStr = parts[1];
        std::string moveStr = parts[2];
        Player pla;
        if (colorStr == "black" || colorStr == "b" || colorStr == "B") pla = P_BLACK;
        else if (colorStr == "white" || colorStr == "w" || colorStr == "W") pla = P_WHITE;
        else return "? invalid color";

        Loc moveLoc = Location::ofString(moveStr, bot->getRootBoard());
        if (moveLoc == Board::NULL_LOC && moveStr != "pass" && moveStr != "PASS") return "? invalid move";

        if (!bot->makeMove(moveLoc, pla)) {
            return "? illegal move";
        }
        return "= ";
    }

    if (mainCmd == "clear_board") {
        Rules rules = bot->getRootHist().rules;
        int xSize = bot->getRootBoard().x_size;
        int ySize = bot->getRootBoard().y_size;
        Board board(xSize, ySize);
        Player pla = P_BLACK;
        BoardHistory hist(board, pla, rules, 0);
        bot->setPosition(pla, board, hist);
        return "= ";
    }

    if (mainCmd == "kata-get-analysis") {
        nlohmann::json json;
        Player perspective = bot->getRootPla();
        if (parts.size() >= 2) {
            std::string pStr = parts[1];
            if (pStr == "black" || pStr == "b") perspective = P_BLACK;
            else if (pStr == "white" || pStr == "w") perspective = P_WHITE;
        }

        bool success = bot->getSearch()->getAnalysisJson(
            perspective, 10, false, true, true, false, false, false, true, false, json
        );

        if (!success) return "? failed to get analysis";
        return "= " + json.dump();
    }

    return "= ok";
}

void KataGoBridge::shutdown() {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (!initialized) return;

    bot->stopAndWait();
    bot.reset();
    if(g_nnEval != nullptr) {
        delete g_nnEval;
        g_nnEval = nullptr;
    }
    logger.reset();
    seedRand.reset();
    initialized = false;
}
