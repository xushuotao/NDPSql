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
#include <chrono>
#include <ctime>
#include <functional>

#include "dbengines.h"


std::string db_path = "/mnt/nvme0/shuotao/tpch/.farms/monetdb-sf300/bat/";
std::string shipdate = "10/1051";
std::string l_returnflag = "10/1047";
std::string l_linestatus = "10/1050";
std::string l_quantity = "10/1043";
std::string l_extendedprice = "10/1044";
std::string l_discount = "10/1045";
std::string l_tax = "10/1046";
// size_t nRows = 1799989091;
size_t nRows = 1799989091/10000;//8192000;
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
  std::string fname_shipdate = db_path+shipdate+".tail";

  auto date_rec = mapfile(fname_shipdate.c_str());
  
  auto pos = select((int*)date_rec->base, nRows, INT_MIN, 729999);
  fprintf(stderr, "pos count = %lu, filter rate = (%lu/%lu) %.2f\n", pos->batCount, pos->batCount, nRows, (float)pos->batCount/(float)nRows*100.0);

  std::string fname_returnflag = db_path+l_returnflag+".tail";
  auto returnflag_rec = mapfile(fname_returnflag.c_str());

  BAT* grp_rf, *ext_rf, *hist_rf;

  auto stat = group((bte*)(returnflag_rec->base), nRows, pos, NULL, NULL,  &grp_rf, &ext_rf, &hist_rf);
  assert(stat == GDK_SUCCEED);
  fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp_rf), BATcount(hist_rf), BATcount(ext_rf));

  std::string fname_linestatus = db_path+l_linestatus+".tail";
  auto linestatus_rec = mapfile(fname_linestatus.c_str());

  BAT* grp=NULL, *ext, *hist;

  stat = group((bte*)(linestatus_rec->base), nRows, pos, grp_rf, ext_rf, &grp, &ext, &hist);
  assert(stat == GDK_SUCCEED);
  fprintf(stderr, "grp->cnt = %lu, hist->cnt = %lu, ext->cnt = %lu\n", BATcount(grp), BATcount(hist), BATcount(ext));

  for ( int i = 0; i < BATcount(hist); i++ ){
    fprintf(stderr, "group %d count = %lld\n", i, ((lng*)Tloc(hist,0))[i]);
  }

  BATclear(grp_rf,0);
  BATclear(ext_rf,0);
  BATclear(hist_rf,0);

  
  std::string fname_quantity = db_path+l_quantity+".tail";
  auto quantity_rec = mapfile(fname_quantity.c_str());

  BAT* sum_quantity;
  stat = aggr_sum<lng,int>((int*)(quantity_rec->base), nRows, pos, grp, hist, &sum_quantity);
  assert(stat == GDK_SUCCEED);
  for ( int i = 0; i < BATcount(sum_quantity); i++ ){
    fprintf(stderr, "group %d sum_quantity = %lld\n", i, ((lng*)Tloc(sum_quantity,0))[i]);
  }

  std::string fname_extendedprice = db_path+l_extendedprice+".tail";
  auto extendedprice_rec = mapfile(fname_extendedprice.c_str());

  BAT* sum_extendedprice;
  stat = aggr_sum<lng, lng>((lng*)(extendedprice_rec->base), nRows, pos, grp, hist, &sum_extendedprice);
  assert(stat == GDK_SUCCEED);
  for ( int i = 0; i < BATcount(sum_extendedprice); i++ ){
    fprintf(stderr, "group %d sum_extendedprice = %.2lf\n", i, (((lng*)Tloc(sum_extendedprice,0))[i])/100.0);
  }

  
  std::string fname_discount = db_path+l_discount+".tail";
  auto discount_rec = mapfile(fname_discount.c_str());

  BAT* sum_discount;
  stat = aggr_sum<lng, lng>((lng*)(discount_rec->base), nRows, pos, grp, hist, &sum_discount);
  assert(stat == GDK_SUCCEED);
  for ( int i = 0; i < BATcount(sum_discount); i++ ){
    fprintf(stderr, "group %d sum_discount = %.2lf\n", i, (((lng*)Tloc(sum_discount,0))[i])/100.0);
  }


  BAT* disc_price = merge<lng>((lng*)(extendedprice_rec->base), nRows, pos, (lng*)(discount_rec->base), nRows, pos,
                                [](lng price, ulng disc) -> lng { return price*(100-disc);});


  BAT* sum_disc_price;
  stat = aggr_sum<lng, lng>((lng*)Tloc(disc_price,0), BATcount(disc_price), NULL, grp, hist, &sum_disc_price);
  assert(stat == GDK_SUCCEED);
  for ( int i = 0; i < BATcount(sum_disc_price); i++ ){
    fprintf(stderr, "group %d sum_disc_price = %.4lf\n", i, (((lng*)Tloc(sum_disc_price,0))[i])/10000.0);
  }


  std::string fname_tax = db_path+l_tax+".tail";
  auto tax_rec = mapfile(fname_tax.c_str());

  BAT* charge = merge<ulng>((ulng*)Tloc(disc_price,0), BATcount(disc_price), NULL, (ulng*)(tax_rec->base), nRows, pos,
                                [](ulng price, ulng disc) -> lng { return price*(100+disc);});



  BAT* sum_charge;
  stat = aggr_sum<hge, lng>((lng*)Tloc(charge,0), BATcount(charge), NULL, grp, hist, &sum_charge);
  assert(stat == GDK_SUCCEED);
  for ( int i = 0; i < BATcount(sum_charge); i++ ){
    fprintf(stderr, "group %d sum_charge = %.6lf\n", i, (((hge*)Tloc(sum_charge,0))[i])/1000000.0);
  }

  fprintf(stderr, "|%25s|%25s|%25s|%25s|%25s|%25s|%25s|%25s|%25s|\n", "group id","sum_qty", "sum_base_price", "sum_disc_price", "sum_charge", "avg_qty", "avg_price", "avg_disc", "count_order");
  for ( int i = 0; i < BATcount(hist); i++ ){
    fprintf(stderr, "|%25d|%25lld|%25.2lf|%25.4lf|%25.6lf|%25.6lf|%25.6lf|%25.6lf|%25lld|\n",
            i,
            ((lng*)Tloc(sum_quantity,0))[i],
            (((lng*)Tloc(sum_extendedprice,0))[i])/100.0,
            (((lng*)Tloc(sum_disc_price,0))[i])/10000.0,
            (((hge*)Tloc(sum_charge,0))[i])/1000000.0,
            (((lng*)Tloc(sum_quantity,0))[i])/(dbl)(((lng*)Tloc(hist,0))[i]), //avg_qty
            (((lng*)Tloc(sum_extendedprice,0))[i])/100.0/(((lng*)Tloc(hist,0))[i]), //avg_price
            (((lng*)Tloc(sum_discount,0))[i])/100.0/(((lng*)Tloc(hist,0))[i]), //avg_disc
            ((lng*)Tloc(hist,0))[i]);
  }


  
  BATclear(pos,0);
  unmapfile(extendedprice_rec);

  unmapfile(quantity_rec);

  unmapfile(linestatus_rec);
  unmapfile(returnflag_rec);
  unmapfile(date_rec);
  return 0;
}

