#!/usr/bin/python
import argparse, json, os, re, string, subprocess, sys, math

def generateFile(args, bsvmodule, context_size):
    synthFileData = ""
    log_cntx_max = math.log(context_size,2)
    typename_string = args.data_type.replace("#","").replace(")","").replace("(","_")
    for log_cntx in range(0, int(log_cntx_max)+1):
        cntx = 1<<log_cntx
        # print log_cntx, cntx
        synthFileTemplate = string.Template(open("synth"+bsvmodule+".template", "r").read())
        synthFileData = synthFileData + synthFileTemplate.substitute(
            VECSZ = args.vector_size,
            CNTX = cntx,
            TYPE = args.data_type,
            TYPENAME = typename_string.lower(),
        )
        
    synthFile = os.path.join("../", "Synth"+bsvmodule+"_"+typename_string+"_"+str(args.vector_size)+".bsv");
    try:
        f = open(synthFile, "w")
        f.write(synthFileData)
        f.close()
    except:
        print "Could not write to synthesis wrapper file", synthFile
        sys.exit(1)
        



if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("context_size", type=int, help="Contex size of your module")
    parser.add_argument("vector_size", type=int, help="Vector Size of your module.")
    parser.add_argument("data_type",  help="Data type of your module")
    args = parser.parse_args()

    generateFile(args, "TopHalf", args.context_size)
    generateFile(args, "Merger", args.context_size)
    generateFile(args, "MergerScheduler", 1)
