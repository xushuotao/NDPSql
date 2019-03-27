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

  auto mask = select<char>((char*)c_mktsegment_rec->base, rows_customers, (char)(pos-GDK_VAROFFSET), pos-GDK_VAROFFSET);

  unmapfile(c_mktsegment_rec);

  fprintf(stderr, "mask count = %lu, filter rate = (%lu/%lu) %.2f\n", BATcount(mask), BATcount(mask), rows_customers, (float)BATcount(mask)/(float)rows_customers*100.0);

  // auto pos = select_date((int*)date_rec->base, nRows, INT_MIN, 729999);
  // fprintf(stderr, "pos count = %lu, filter rate = (%lu/%lu) %.2f\n", pos->batCount, pos->batCount, nRows, (float)pos->batCount/(float)nRows*100.0);

  // std::string fname_returnflag = db_path+l_returnflag+".tail";
  // auto returnflag_rec = mapfile(fname_returnflag.c_str());

  // BAT* grp_rf, *ext_rf, *hist_rf;

  // auto stat = group((bte*)(returnflag_rec->base), nRows, pos, NULL, NULL,  &grp_rf, &ext_rf, &hist_rf);
  // assert(stat == GDK_SUCCEED);
  // fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp_rf), BATcount(hist_rf), BATcount(ext_rf));

  // std::string fname_linestatus = db_path+l_linestatus+".tail";
  // auto linestatus_rec = mapfile(fname_linestatus.c_str());

  // BAT* grp=NULL, *ext, *hist;

  // stat = group((bte*)(linestatus_rec->base), nRows, pos, grp_rf, ext_rf, &grp, &ext, &hist);
  // assert(stat == GDK_SUCCEED);
  // fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp), BATcount(hist), BATcount(ext));

  // for ( int i = 0; i < BATcount(hist); i++ ){
  //   fprintf(stderr, "group %d count = %lld\n", i, ((lng*)Tloc(hist,0))[i]);
  // }

  // BATclear(grp_rf,0);
  // BATclear(ext_rf,0);
  // BATclear(hist_rf,0);

  
  // std::string fname_quantity = db_path+l_quantity+".tail";
  // auto quantity_rec = mapfile(fname_quantity.c_str());

  // BAT* sum_quantity;
  // stat = aggr_sum<lng,int>((int*)(quantity_rec->base), nRows, pos, grp, hist, &sum_quantity);
  // assert(stat == GDK_SUCCEED);
  // for ( int i = 0; i < BATcount(sum_quantity); i++ ){
  //   fprintf(stderr, "group %d sum_quantity = %lld\n", i, ((lng*)Tloc(sum_quantity,0))[i]);
  // }

  // std::string fname_extendedprice = db_path+l_extendedprice+".tail";
  // auto extendedprice_rec = mapfile(fname_extendedprice.c_str());

  // BAT* sum_extendedprice;
  // stat = aggr_sum<lng, lng>((lng*)(extendedprice_rec->base), nRows, pos, grp, hist, &sum_extendedprice);
  // assert(stat == GDK_SUCCEED);
  // for ( int i = 0; i < BATcount(sum_extendedprice); i++ ){
  //   fprintf(stderr, "group %d sum_extendedprice = %.2lf\n", i, (((lng*)Tloc(sum_extendedprice,0))[i])/100.0);
  // }

  
  // std::string fname_discount = db_path+l_discount+".tail";
  // auto discount_rec = mapfile(fname_discount.c_str());

  // BAT* sum_discount;
  // stat = aggr_sum<lng, lng>((lng*)(discount_rec->base), nRows, pos, grp, hist, &sum_discount);
  // assert(stat == GDK_SUCCEED);
  // for ( int i = 0; i < BATcount(sum_discount); i++ ){
  //   fprintf(stderr, "group %d sum_discount = %.2lf\n", i, (((lng*)Tloc(sum_discount,0))[i])/100.0);
  // }


  // BAT* disc_price = merge<lng>((lng*)(extendedprice_rec->base), nRows, pos, (lng*)(discount_rec->base), nRows, pos,
  //                               [](lng price, ulng disc) -> lng { return price*(100-disc);});


  // BAT* sum_disc_price;
  // stat = aggr_sum<lng, lng>((lng*)Tloc(disc_price,0), BATcount(disc_price), NULL, grp, hist, &sum_disc_price);
  // assert(stat == GDK_SUCCEED);
  // for ( int i = 0; i < BATcount(sum_disc_price); i++ ){
  //   fprintf(stderr, "group %d sum_disc_price = %.4lf\n", i, (((lng*)Tloc(sum_disc_price,0))[i])/10000.0);
  // }


  // std::string fname_tax = db_path+l_tax+".tail";
  // auto tax_rec = mapfile(fname_tax.c_str());

  // BAT* charge = merge<ulng>((ulng*)Tloc(disc_price,0), BATcount(disc_price), NULL, (ulng*)(tax_rec->base), nRows, pos,
  //                               [](ulng price, ulng disc) -> lng { return price*(100+disc);});

  

  // BAT* sum_charge;
  // stat = aggr_sum<hge, lng>((lng*)Tloc(charge,0), BATcount(charge), NULL, grp, hist, &sum_charge);
  // assert(stat == GDK_SUCCEED);
  // for ( int i = 0; i < BATcount(sum_charge); i++ ){
  //   fprintf(stderr, "group %d sum_charge = %.6lf\n", i, (((hge*)Tloc(sum_charge,0))[i])/1000000.0);
  // }

  // fprintf(stderr, "|%25s|%25s|%25s|%25s|%25s|%25s|%25s|%25s|%25s|\n", "group id","sum_qty", "sum_base_price", "sum_disc_price", "sum_charge", "avg_qty", "avg_price", "avg_disc", "count_order");
  // for ( int i = 0; i < BATcount(hist); i++ ){
  //   fprintf(stderr, "|%25d|%25lld|%25.2lf|%25.4lf|%25.6lf|%25.6lf|%25.6lf|%25.6lf|%25lld|\n",
  //           i,
  //           ((lng*)Tloc(sum_quantity,0))[i],
  //           (((lng*)Tloc(sum_extendedprice,0))[i])/100.0,
  //           (((lng*)Tloc(sum_disc_price,0))[i])/10000.0,
  //           (((hge*)Tloc(sum_charge,0))[i])/1000000.0,
  //           (((lng*)Tloc(sum_quantity,0))[i])/(dbl)(((lng*)Tloc(hist,0))[i]), //avg_qty
  //           (((lng*)Tloc(sum_extendedprice,0))[i])/100.0/(((lng*)Tloc(hist,0))[i]), //avg_price
  //           (((lng*)Tloc(sum_discount,0))[i])/100.0/(((lng*)Tloc(hist,0))[i]), //avg_disc
  //           ((lng*)Tloc(hist,0))[i]);
  // }


  
  // BATclear(pos,0);
  // unmapfile(extendedprice_rec);

  // unmapfile(quantity_rec);

  // unmapfile(linestatus_rec);
  // unmapfile(returnflag_rec);
  // unmapfile(date_rec);
  return 0;
}

