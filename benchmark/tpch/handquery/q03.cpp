#include <vector>
#include <string>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <assert.h>
#include <limits.h>
#include <omp.h>

#include <ctime>

#include <iostream>

#include "dbengines.h"


std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
std::string l_shipdate = "10/1051"; // int
std::string l_orderkey = "07/752"; // int
size_t rows_lineitem = 1799989091;
std::string c_mktsegment = "03/344"; // varchar 8-byte
std::string c_custkey = "04/425"; //int
size_t rows_customers = 45000000;
std::string o_orderdate = "07/746"; // int
std::string o_orderkey = "04/437"; // int
std::string o_custkey = "07/755"; // int
size_t rows_orders = 450000000;


// size_t nRows = 100000;


int main(){
  opt* set = NULL;
  int setlen = mo_builtin_settings(&set);
  char mem_size_c[1024];
  sprintf(mem_size_c, "%lu", 20*1024*1024*1024UL);
  setlen = mo_add_option(&set, setlen, opt_config, "gdk_mmap_minsize_transient", mem_size_c);
  mo_print_options(set, setlen);
  char *currdir = get_current_dir_name();
  char *dbpath = strcat(currdir, "/dbpath");
  GDKcreatedir(dbpath);
  BBPaddfarm(dbpath, 1 << PERSISTENT);
  BBPaddfarm(dbpath, 1 << TRANSIENT);
  GDKinit(set, setlen);
  std::string fname_c_mktsegment = db_path+c_mktsegment+".tail";
  std::string fname_c_mktsegment_vheap = db_path+c_mktsegment+".theap";

  // auto c_mktsegment_rec = mapfile(fname_c_mksegment.c_str());
  // auto c_mktsegment_rec = mapfile(fname_c_mksegment.c_str());

  auto c_mksegment_vheap_rec = mapfile(fname_c_mktsegment_vheap.c_str());
  
  Heap* vh = (Heap*) GDKzalloc(sizeof(Heap));
  // vh->hashash = 1;
  vh->base = (char*)c_mksegment_vheap_rec->base;

  var_t pos;

  pos = strLocate(vh, "BUILDING");

  fprintf(stderr,"pos == %lu, GDK_OFFSET=%lu, %s\n",pos, GDK_VAROFFSET,(vh->base)+pos);

  unmapfile(c_mksegment_vheap_rec);

  auto c_mktsegment_rec = mapfile(fname_c_mktsegment.c_str());

  auto mask_cust = select<char>((char*)c_mktsegment_rec->base, rows_customers, (char)(pos-GDK_VAROFFSET), pos-GDK_VAROFFSET);

  unmapfile(c_mktsegment_rec);

  fprintf(stderr, "mask_cust count = %lu, filter rate = (%lu/%lu) %.2f\n", BATcount(mask_cust), BATcount(mask_cust), rows_customers, (float)BATcount(mask_cust)/(float)rows_customers*100.0);


  std::string fname_o_orderdate = db_path+o_orderdate+".tail";
  auto o_orderdate_rec = mapfile(fname_o_orderdate.c_str());

  auto mask_order = select<int>((int*)o_orderdate_rec->base, rows_orders, INT_MIN, todate(15, 03, 1995)-1);

  fprintf(stderr, "mask_order count = %lu, filter rate = (%lu/%lu) %.2f\n", BATcount(mask_order), BATcount(mask_order), rows_orders, (float)BATcount(mask_order)/(float)rows_orders*100.0);

  std::string fname_o_custkey = db_path+o_custkey+".tail";
  auto o_custkey_rec = mapfile(fname_o_custkey.c_str());
  BAT* o_custkey_bat = maptoBAT(o_custkey_rec, TYPE_int, rows_orders);

  
  std::string fname_c_custkey = db_path+c_custkey+".tail";
  auto c_custkey_rec = mapfile(fname_c_custkey.c_str());
  BAT* c_custkey_bat = maptoBAT(c_custkey_rec, TYPE_int, rows_customers);

  fprintf(stderr, "|%25s|%25s|%25s|\n", "c_custkey","o_custkey", "o_orderdate");
  str date_str = (str)GDKmalloc(15);
  int len = 15;
  for (int i = 0; i < 10; i++ ){
    BUN cust_p = ((BUN*)Tloc(mask_cust,0))[i];
    BUN order_p = ((BUN*)Tloc(mask_order,0))[i];
    date_tostr(&date_str, &len, ((date*)(o_orderdate_rec->base))+order_p);
    fprintf(stderr, "|%25d|%25d|%25s|\n", ((int*)Tloc(c_custkey_bat,0))[cust_p],((int*)Tloc(o_custkey_bat,0))[order_p], date_str);
  }

  BAT *lid, *rid;
  auto proj_o_custkey = BATproject(mask_order, o_custkey_bat);
  // BATsetcount(proj_o_custkey, BATcount(proj_o_custkey)/10);
  auto status = BATjoin(&lid, &rid, BATproject(mask_cust, c_custkey_bat), proj_o_custkey, NULL, NULL, 0, 0);

  fprintf(stderr, "(c and o join result on custkey) lid->batCount = %ld, rid->batCount = %ld\n", BATcount(lid), BATcount(rid));

   
  fprintf(stderr, "|%25s|%25s|%25s|%25s|%25s|\n", "cust_ptr", "c_custkey", "order_ptr", "o_custkey", "o_orderdate");
  for (int i = 0; i < 10; i++ ){
    BUN cust_p = ((BUN*)Tloc(lid,0))[i];
    BUN order_p = ((BUN*)Tloc(rid,0))[i];
    date_tostr(&date_str, &len, ((date*)(o_orderdate_rec->base))+order_p);
    fprintf(stderr, "|%25lu|%25d|%25lu|%25d|%25s|\n", cust_p, ((int*)Tloc(c_custkey_bat,0))[cust_p], order_p, ((int*)Tloc(o_custkey_bat,0))[order_p], date_str);
  }
  

  // std::string fname_l_shipdate = db_path+l_shipdate+".tail";
  // auto l_shipdate_rec = mapfile(fname_l_shipdate.c_str());

  // auto mask_lineitem = select<int>((int*)l_shipdate_rec->base, rows_lineitem, todate(15, 03, 1995)+1, INT_MAX);

  // fprintf(stderr, "mask_lineitem count = %lu, filter rate = (%lu/%lu) %.2f\n", BATcount(mask_lineitem), BATcount(mask_lineitem), rows_lineitem, (float)BATcount(mask_lineitem)/(float)rows_lineitem*100.0);

  // std::string fname_l_orderkey = db_path+l_orderkey+".tail";
  // auto l_orderkey_rec = mapfile(fname_l_orderkey.c_str());
  // BAT* l_orderkey_bat = maptoBAT(l_orderkey_rec, TYPE_int, rows_lineitem);


  // std::string fname_o_orderkey = db_path+o_orderkey+".tail";
  // auto o_orderkey_rec = mapfile(fname_o_orderkey.c_str());
  // BAT* o_orderkey_bat = maptoBAT(o_orderkey_rec, TYPE_int, rows_orders);


  // BAT *lid_1, *rid_1;

  // status = BATjoin(&lid_1, &rid_1, BATproject(mask_lineitem, l_orderkey_bat), BATproject(rid, o_orderkey_bat), NULL, NULL, 0, 0);
  


  unmapfile(o_orderdate_rec);


  return 0;
}


