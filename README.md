NDPSql
====

Near-data SQL Processing: in-storage computation to offload some of the MonetDB SQL
operators inside flash drives to boost SQL query performance on both a single servers
and a cluster of servers.  We propose to investigate seven important SQL operators
for the benefit of in-storage processing: filter, projection, join, sort, indexing,
groupby, and topk.

Building NDPSql
====

Preparing the NDPSql Building Environment
-------------------------  

1. Checkout out the following from github:

       git clone git://github.com/xushuotao/NDPSql --recursive
   
2. Install the bluespec compiler. Make sure the BLUESPECDIR environment variable
   is set appropriately:

       export BLUESPECDIR=~/bluespec/Bluespec-2014.07.A/lib

3. Install Vivado 2018.1

            

Current NDPSql projects
-----------------------------
Projects are located in folder projects. Current projects are


Project | Description
--------------|----------
flash_dual_test | Test the raw erase/write/read speed of dual flash cards without going over PCIE
flash_dual | Test the raw erase/write/read functionality of dual flash cards going over PCIE gen2 using DMA
fakeflash_dual | Test the PCIE gen2 transfer speed using fake flash card traffic generator


Building NDPSql projects from source
-----------------------------

 cd to the NDPSql directory, then type

    cd projects/<project>
    make build.<target> -j

where target is

target | Function
--------------|----------
verilator | compile for verilog simulation
vc707g2| compile for vc707 fpga board with pcie gen2 core

If you target is verilator, you can just run the simulation by running

    ./verilator/bin/ubuntu.exe


Building ONLY the software NDPSql projects from source
-----------------------------

To save time, the pre-compiled bit files of the projects are in

    projects/<project>/hw/mkTop.bit

and you can just build the software and skipping the time-consuming fpga compilation by

    cd projects/<project>
    make gen.<target>
    cd <target>
    make exe -j


Running NDPSql
======

The below is assumming build server and run server are separate.


Preparing the FPGA Running Environment
-------------------------

1. Setup the server and FPGA boards as Section 5 in the BlueDBM paper (ISCA'15)
   [http://livinglab.mit.edu/wp-content/uploads/2016/01/ISCA15_Sang-Woo_Jun.pdf]

2. Install Vivado 2018.1

3. Install Connectal Drivers

       sudo add-apt-repository -y ppa:jamey-hicks/connectal
       sudo apt-get update
       sudo apt-get -y install connectal

4. Copy running scripts and FPGA bit images to the server with the Xilinx FPGA by running:

       scp scripts/running_scripts/* <server_url>:

5. Source setup.sh for setting up the environment variable by appending the bash.sh

       echo "source ~/setup.sh" >> ~/.bashrc


Running NDPSql projects
-------------------------

0. Copy your project target folder to the running machine

       scp -r projects/<project>/vc707g2 <server_url>:.

1. Program FPGAs by running:

       ./program.sh

   You might have to change the program-valid-all.tcl file to point to the correct fpga bit file.

2. Rescan the portals by running:

       pciescanportal


3. Run the software binary by running:

       NOPROGRAM=1 ./vc707g2/bin/ubuntu.exe


You can just repeat step 3 if not fpga is not reprogrammed.
