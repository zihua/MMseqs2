#include "DBWriter.h"
#include "Debug.h"
#include "Parameters.h"
#include "DBReader.h"
#include "Util.h"
#include "Matcher.h"
#include "FileUtil.h"

#ifdef OPENMP
#include <omp.h>
#endif

#include <sys/time.h>

int doExtractAlignedRegion(Parameters &par) {
    DBReader<unsigned int> *qdbr = NULL;
    DBReader<unsigned int> *tdbr = NULL;

    bool sameDB = false;
    Debug(Debug::INFO) << "Query  file: " << par.db1 << "\n";
    qdbr = new DBReader<unsigned int>(par.db1.c_str(), par.db1Index.c_str());
    qdbr->open(DBReader<unsigned int>::NOSORT);
    qdbr->readMmapedDataInMemory();

    Debug(Debug::INFO) << "Target  file: " << par.db2 << "\n";
    if (par.db1.compare(par.db2) == 0) {
        sameDB = true;
        tdbr = qdbr;
    } else {
        tdbr = new DBReader<unsigned int>(par.db2.c_str(), par.db2Index.c_str());
        tdbr->open(DBReader<unsigned int>::NOSORT);
        tdbr->readMmapedDataInMemory();
    }

    Debug(Debug::INFO) << "Alignment database: " << par.db3 << "\n";
    DBReader<unsigned int> alndbr(par.db3.c_str(), par.db3Index.c_str());
    alndbr.open(DBReader<unsigned int>::LINEAR_ACCCESS);

    DBWriter dbw(par.db4.c_str(), par.db4Index.c_str(), static_cast<unsigned int>(par.threads));
    dbw.open();

    Debug(Debug::INFO) << "Start writing file to " << par.db4 << "\n";
#pragma omp for schedule(dynamic, 1000)
    for (size_t i = 0; i < alndbr.getSize(); i++) {
        unsigned int thread_idx = 0;
#ifdef OPENMP
        thread_idx = static_cast<unsigned int>(omp_get_thread_num());
#endif
        unsigned int queryKey = alndbr.getDbKey(i);
        char *qSeq = NULL;
        if (par.extractMode == Parameters::EXTRACT_QUERY) {
            qSeq = qdbr->getDataByDBKey(queryKey);
        }

        char *data = alndbr.getData(i);
        std::vector<Matcher::result_t> results = Matcher::readAlignmentResults(data);
        for (size_t j = 0; j < results.size(); j++) {
            Matcher::result_t res = results[j];
            size_t length = 0;
            char* seq = NULL;
            if (qSeq) {
                seq = qSeq + res.qStartPos;
                length = res.qEndPos - res.qStartPos;
            } else if (par.extractMode == Parameters::EXTRACT_TARGET) {
                seq = tdbr->getDataByDBKey(res.dbKey) + res.dbStartPos;
                length = res.dbEndPos - res.dbStartPos;
            }

            if (seq) {
                std::string result(seq, length);
                result.append("\n");
                dbw.writeData(result.c_str(), result.length(), queryKey, thread_idx);
            } else {
                Debug(Debug::ERROR) << "Missing extraction type!\n";
                EXIT(EXIT_FAILURE);
            }
        }
    }
    dbw.close();

    std::string base = FileUtil::baseName(par.db4 + "_h");
    FileUtil::symlinkAlias(par.db1 + "_h", base);
    FileUtil::symlinkAlias(par.db1 + "_h.index", base + ".index");

    Debug(Debug::INFO) << "Done." << "\n";

    alndbr.close();
    qdbr->close();
    delete qdbr;
    if (sameDB == false) {
        tdbr->close();
        delete tdbr;
    }

    return EXIT_SUCCESS;
}

int extractalignedregion(int argc, const char **argv, const Command& command) {
    Parameters& par = Parameters::getInstance();
    par.parseParameters(argc, argv, command, 4);

    // never allow deletions
    par.allowDeletion = false;
    struct timeval start, end;
    gettimeofday(&start, NULL);

    int retCode = doExtractAlignedRegion(par);

    gettimeofday(&end, NULL);
    time_t sec = end.tv_sec - start.tv_sec;
    Debug(Debug::INFO) << "Time for processing: " << (sec / 3600) << " h " << (sec % 3600 / 60) << " m " << (sec % 60) << "s\n";

    return retCode;
}

