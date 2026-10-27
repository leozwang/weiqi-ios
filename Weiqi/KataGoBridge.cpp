#include "KataGoBridge.hpp"
#include <vector>
#include <thread>
#include <mutex>
#include <iostream>
#include <sstream>
#include <cmath>

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

    // Parses a GTP color argument ("b", "black", "w", "white"; any case).
    bool parsePlayer(const std::string& s, Player& pla) {
        const std::string lower = Global::toLower(s);
        if (lower == "b" || lower == "black") { pla = P_BLACK; return true; }
        if (lower == "w" || lower == "white") { pla = P_WHITE; return true; }
        return false;
    }

    // Moves must strictly alternate. AsyncBot/Search silently wipe the game record when asked
    // to move or search for the side that is not to play, which breaks undo and ko tracking.
    int turnRefusals = 0;  // how often the app asked for the wrong color (tests require 0)
    std::string notYourTurn(Player pla) {
        turnRefusals++;
        return std::string("? not ") + (pla == P_BLACK ? "black" : "white") + "'s turn";
    }

    // Root visits of the last genmove search, i.e. what the difficulty level's budget limits.
    int64_t lastSearchVisits = 0;

    // Executes one command. Caller must hold engineMutex and the engine must be initialized.
    std::string runCommand(const std::string& command) {
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

        if (mainCmd == "get_komi") {
            return "= " + Global::strprintf("%.1f", bot->getRootHist().rules.komi);
        }

        // Read-only view of the search limits (used by tests to check the difficulty levels).
        if (mainCmd == "kata-get-param") {
            if (parts.size() < 2) return "? missing parameter";
            const SearchParams& params = bot->getParams();
            if (parts[1] == "maxVisits") return "= " + std::to_string(params.maxVisits);
            if (parts[1] == "maxPlayouts") return "= " + std::to_string(params.maxPlayouts);
            if (parts[1] == "numSearchThreads") return "= " + std::to_string(params.numThreads);
            return "? unknown parameter";
        }

        // Number of out-of-turn requests refused since the engine started (turn-order audit).
        if (mainCmd == "get_turn_refusals") {
            return "= " + std::to_string(turnRefusals);
        }

        // Visits of the last genmove search (tests check them against the difficulty level).
        if (mainCmd == "get_last_search_visits") {
            return "= " + std::to_string(lastSearchVisits);
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
            Player pla;
            if (parts.size() < 2 || !parsePlayer(parts[1], pla)) return "? missing or invalid color";
            if (pla != bot->getRootPla()) return notYourTurn(pla);
            TimeControls tc;
            Loc moveLoc = bot->genMoveSynchronous(pla, tc);
            lastSearchVisits = bot->getSearch()->getRootVisits();
            std::string moveStr = Location::toString(moveLoc, bot->getRootBoard());
            bot->makeMove(moveLoc, pla);
            return "= " + moveStr;
        }

        if (mainCmd == "think") {
            Player pla;
            if (parts.size() < 2 || !parsePlayer(parts[1], pla)) return "? missing or invalid color";
            if (pla != bot->getRootPla()) return notYourTurn(pla);
            int64_t visits = 400;
            if (parts.size() >= 3) {
                try { visits = std::stoll(parts[2]); } catch (...) { return "? invalid visits"; }
            }
            SearchParams oldParams = bot->getParams();
            SearchParams newParams = oldParams;
            newParams.maxVisits = visits; newParams.maxPlayouts = visits;
            bot->setParamsNoClearing(newParams);
            bot->genMoveSynchronous(pla, TimeControls());
            bot->setParamsNoClearing(oldParams);
            return "= ";
        }

        if (mainCmd == "play") {
            Player pla;
            if (parts.size() < 3 || !parsePlayer(parts[1], pla)) return "? missing color or move";
            if (pla != bot->getRootPla()) return notYourTurn(pla);
            Loc moveLoc;
            if (!Location::tryOfString(parts[2], bot->getRootBoard(), moveLoc)) return "? invalid move";
            // makeMove() alone is "tolerant" (it accepts multi-stone suicide whatever the rules say),
            // so validate against the configured rules first.
            if (!bot->isLegalStrict(moveLoc, pla)) return "? illegal move";
            if (!bot->makeMove(moveLoc, pla)) return "? illegal move";
            return "= ";
        }

        if (mainCmd == "undo") {
            const BoardHistory& hist = bot->getRootHist();
            if (hist.moveHistory.size() == 0) return "? cannot undo";
            Board board = hist.initialBoard;
            BoardHistory newHist(board, hist.initialPla, hist.rules, hist.initialEncorePhase);
            newHist.setAssumeMultipleStartingBlackMovesAreHandicap(hist.assumeMultipleStartingBlackMovesAreHandicap);
            newHist.setInitialTurnNumber(hist.initialTurnNumber);
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

        if (mainCmd == "fixed_handicap") {
            if (parts.size() < 2) return "? missing count";
            int n = 0;
            try { n = std::stoi(parts[1]); } catch (...) { return "? invalid count"; }
            if (n < 1 || n > 9) return "? invalid count";
            int xSize = bot->getRootBoard().x_size;
            int ySize = bot->getRootBoard().y_size;
            Board board(xSize, ySize);
            if (n == 1) {
                int xCoord = (xSize <= 12) ? xSize - 3 : xSize - 4;
                int yCoord = (ySize <= 12) ? 2 : 3;
                board.setStone(Location::getLoc(xCoord, yCoord, board.x_size), P_BLACK);
            } else {
                try {
                    PlayUtils::placeFixedHandicap(board, n);
                } catch (const StringError& e) {
                    return "? " + std::string(e.what());
                }
            }
            BoardHistory hist(board, P_WHITE, bot->getRootHist().rules, 0);
            hist.clear(board, P_WHITE, bot->getRootHist().rules, 0);
            hist.setAssumeMultipleStartingBlackMovesAreHandicap(true);
            hist.setInitialTurnNumber(board.numStonesOnBoard());
            bot->setPosition(P_WHITE, board, hist);

            std::string resp = "= ";
            for (int y = 0; y < board.y_size; y++) {
                for (int x = 0; x < board.x_size; x++) {
                    Loc loc = Location::getLoc(x, y, board.x_size);
                    if (board.colors[loc] != C_EMPTY) {
                        resp += Location::toString(loc, board) + " ";
                    }
                }
            }
            return resp;
        }

        // "= <361 cells> <black's captures> <white's captures> <side to move B|W>"
        if (mainCmd == "get_board") {
            const Board& b = bot->getRootBoard();
            std::string resp = "= ";
            for (int y = 0; y < b.y_size; y++) {
                for (int x = 0; x < b.x_size; x++) {
                    Player color = b.colors[Location::getLoc(x, y, b.x_size)];
                    if (color == P_BLACK) resp += "1";
                    else if (color == P_WHITE) resp += "2";
                    else resp += "0";
                }
            }
            resp += " " + std::to_string(b.numWhiteCaptures) + " " + std::to_string(b.numBlackCaptures);
            resp += bot->getRootPla() == P_WHITE ? " W" : " B";
            return resp;
        }

        if (mainCmd == "final_score") {
            bot->stopAndWait();
            // computeLead re-roots the search at several probe komi values, so snapshot the real
            // game state and restore it afterwards (as KataGo's own GTP engine does). Otherwise the
            // game would continue with a wrong komi after an undo at game over.
            const SearchParams oldParams = bot->getParams();
            const Player oldPla = bot->getRootPla();
            const Board oldBoard = bot->getRootBoard();
            const BoardHistory oldHist = bot->getRootHist();

            SearchParams scoringParams = oldParams;
            scoringParams.playoutDoublingAdvantage = 0.0;
            scoringParams.conservativePass = true;
            bot->setParams(scoringParams);

            Board board = oldBoard;
            BoardHistory hist = oldHist;
            double lead = PlayUtils::computeLead(bot->getSearchStopAndWait(), NULL, board, hist, oldPla, 500, OtherGameProperties());
            // Round to a result the rules can actually produce (x.5 with a half-point komi).
            if (hist.rules.gameResultWillBeInteger()) lead = std::round(lead);
            else lead = std::round(lead + 0.5) - 0.5;

            bot->setPosition(oldPla, oldBoard, oldHist);
            bot->setParams(oldParams);

            if (lead == 0) return "= 0";
            if (lead < 0) return "= B+" + Global::strprintf("%.1f", -lead);
            return "= W+" + Global::strprintf("%.1f", lead);
        }

        if (mainCmd == "kata-get-analysis") {
            bot->stopAndWait();
            nlohmann::json json;
            Player perspective = P_BLACK;
            if (parts.size() >= 2 && (parts[1] == "white" || parts[1] == "w")) perspective = P_WHITE;
            if (bot->getSearch()->getRootVisits() <= 0) {
                try {
                    SearchParams oldParams = bot->getParams();
                    SearchParams newParams = oldParams;
                    newParams.maxVisits = 50; newParams.maxPlayouts = 50;
                    bot->setParamsNoClearing(newParams);
                    bot->genMoveSynchronous(bot->getRootPla(), TimeControls());
                    bot->setParamsNoClearing(oldParams);
                } catch (...) {}
            }
            if (!bot->getSearch()->getAnalysisJson(perspective, 10, false, true, true, false, false, false, true, false, json)) return "? failed";
            return "= " + json.dump();
        }

        return "= ok";
    }
}

KataGoBridge::KataGoBridge() {}

KataGoBridge::~KataGoBridge() {
    shutdown();
}

int KataGoBridge::initEngine(const std::string& configPath, const std::string& modelPath, const std::string& storagePath) {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (initialized) return 0;

    oneTimeInit();

    try {
        ConfigParser cfg(configPath, true);
        cfg.overrideKey("logAllGTPCommunication", "false");
        cfg.overrideKey("logSearchInfo", "false");
        cfg.overrideKey("logToStderr", "false");
        cfg.overrideKey("logSearchInfoInterval", "-1");
        
        cfg.overrideKey("logDir", storagePath + "/temp_logs");
        cfg.overrideKey("homeDataDir", storagePath);

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
        std::cerr << "KataGo Initialization Exception: " << e.what() << std::endl;
        initialized = false;
        return -1;
    } catch (...) {
        std::cerr << "KataGo Initialization Unknown Exception occurred." << std::endl;
        initialized = false;
        return -1;
    }

    return 0;
}

std::string KataGoBridge::sendGtpCommand(const std::string& command) {
    std::lock_guard<std::mutex> lock(engineMutex);
    if (!initialized) return "? engine not initialized";
    // Never let an engine exception escape into Objective-C/Swift (it would terminate the app).
    try {
        return runCommand(command);
    } catch (const std::exception& e) {
        return "? " + std::string(e.what());
    } catch (...) {
        return "? internal error";
    }
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
