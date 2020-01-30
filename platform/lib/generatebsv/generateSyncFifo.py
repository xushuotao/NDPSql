#!/usr/bin/python
import argparse, json, os, re, string, subprocess, sys, math

def generateFile(args):
    # print log_cntx, cntx
    bsvFileTemplate = string.Template(open("syncFifo.template", "r").read())
    bsvFileData = bsvFileTemplate.substitute(
        WIDTH = args.width,
        DEPTH = args.depth,
    )
        
    bsvFile = os.path.join("../", "XilinxSyncFifoW"+str(args.width)+"D"+str(args.depth)+".bsv");
    try:
        f = open(bsvFile, "w")
        f.write(bsvFileData)
        f.close()
    except:
        print "Could not write to synthesis wrapper file", bsvFile
        sys.exit(1)
        



if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("width", type=int, help="Width of the SyncFIFO")
    parser.add_argument("depth", type=int, help="Depth of the SyncFIFO")
    args = parser.parse_args()

    generateFile(args);
