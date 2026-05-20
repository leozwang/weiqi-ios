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
        cfg.overrideKey("logAllGTPCommunication", "false");
        cfg.overrideKey("logSearchInfo", "false");
        cfg.overrideKey("logToStderr", "false");
        cfg.overrideKey("logSearchInfoInterval", "-1");
        
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
    } catch (...) {
        initialized = false;
        return -1;
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

    if (mainCmd == "komi") {
        if (parts.size() < 2) return "? missing value";
        try { bot->setKomiIfNew(std::stof(parts[1])); } catch (...) { return "? invalid value"; }
        return "= ";
    }

    if (mainCmd == "set_max_visits") {
        if (parts.size() < 2) return "? missing visits";
        try {
            int64_t v = std::stoll(parts[1]);
            SearchParams params = bot->getParams();
            params.maxVisits = v; params.maxPlayouts = v;
            bot->setParams(params);
        } catch (...) { return "? invalid visits"; }
        return "= ";
    }

    if (mainCmd == "genmove") {
        if (parts.size() < 2) return "? missing color";
        std::string colorStr = parts[1];
        Player pla = (colorStr == "white" || colorStr == "w") ? P_WHITE : P_BLACK;
        TimeControls tc;
        Loc moveLoc = bot->genMoveSynchronous(pla, tc);
        std::string moveStr = Location::toString(moveLoc, bot->getRootBoard());
        bot->makeMove(moveLoc, pla);
        return "= " + moveStr;
    }

    if (mainCmd == "think") {
        if (parts.size() < 2) return "? missing color";
        Player pla = (parts[1] == "white" || parts[1] == "w") ? P_WHITE : P_BLACK;
        int64_t visits = (parts.size() >= 3) ? std::stoll(parts[2]) : 400;
        SearchParams oldParams = bot->getParams();
        SearchParams newParams = oldParams;
        newParams.maxVisits = visits; newParams.maxPlayouts = visits;
        bot->setParamsNoClearing(newParams);
        bot->genMoveSynchronous(pla, TimeControls());
        bot->setParamsNoClearing(oldParams);
        return "= ";
    }

    if (mainCmd == "play") {
        if (parts.size() < 3) return "? missing color or move";
        Player pla = (parts[1] == "white" || parts[1] == "w") ? P_WHITE : P_BLACK;
        Loc moveLoc = Location::ofString(parts[2], bot->getRootBoard());
        if (moveLoc == Board::NULL_LOC && parts[2] != "pass" && parts[2] != "PASS") return "? invalid move";
        if (!bot->makeMove(moveLoc, pla)) return "? illegal move";
        return "= ";
    }

    if (mainCmd == "undo") {
        const BoardHistory& hist = bot->getRootHist();
        if (hist.moveHistory.size() == 0) return "? cannot undo";
        Board board = hist.initialBoard;
        BoardHistory newHist(board, hist.initialPla, hist.rules, hist.initialEncorePhase);
        for (size_t i = 0; i < hist.moveHistory.size() - 1; i++) {
            newHist.makeBoardMoveAssumeLegal(board, hist.moveHistory[i].loc, hist.moveHistory[i].pla, nullptr);
        }
        bot->setPosition(newHist.presumedNextMovePla, board, newHist);
        return "= ";
    }

    if (mainCmd == "clear_board") {
        Board board(bot->getRootBoard().x_size, bot->getRootBoard().y_size);
        BoardHistory hist(board, P_BLACK, bot->getRootHist().rules, 0);
        bot->setPosition(P_BLACK, board, hist);
        return "= ";
    }

    if (mainCmd == "final_score") {
        bot->stopAndWait();
        BoardHistory histCopy = bot->getRootHist();
        float score = PlayUtils::computeLead(bot->getSearchStopAndWait(), NULL, bot->getRootBoard(), histCopy, P_WHITE, 500, OtherGameProperties());
        std::string resp = "= ";
        if (score == 0) resp += "0";
        else if (score > 0) resp += "B+" + Global::strprintf("%.1f", score);
        else resp += "W+" + Global::strprintf("%.1f", -score);
        return resp;
    }

    if (mainCmd == "kata-get-analysis") {
        nlohmann::json json;
        Player perspective = P_BLACK;
        if (parts.size() >= 2 && (parts[1] == "white" || parts[1] == "w")) perspective = P_WHITE;
        if (!bot->getSearch()->getAnalysisJson(perspective, 10, false, true, true, false, false, false, true, false, json)) return "? failed";
        return "= " + json.dump();
    }

    return "= ok";
}

void KataGoBridge::shutdown() {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (!initialized) return;
    bot->stopAndWait();
    bot.reset();
    if(g_nnEval != nullptr) { delete g_nnEval; g_nnEval = nullptr; }
    logger.reset(); seedRand.reset();
    initialized = false;
}
