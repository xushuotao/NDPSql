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
size_t nRows = 1799989091/1000;//8192000;
// size_t nRows = 100000;

size_t page_size = 8192;


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

  fprintf(stderr, "lo = %d, hi = %d\n",todate(01, 01, 1994), todate(31, 12, 1994));
  auto pos = select((int*)date_rec->base, nRows, todate(01, 01, 1994), todate(31, 12, 1994));
  fprintf(stderr, "pos count = %lu, filter rate = (%lu/%lu) %.2f%%, numOfPages read = %lu\n", pos->batCount, pos->batCount, nRows, (float)pos->batCount/(float)nRows*100.0, (nRows*sizeof(int)+page_size-1)/page_size);


  std::string fname_discount = db_path+l_discount+".tail";
  auto discount_rec = mapfile(fname_discount.c_str());
  auto discount_bat = maptoBAT(discount_rec, TYPE_lng, nRows);
  BAT* proj_discount = BATproject(pos, discount_bat);
  auto pos_discount = select<lng>((lng*)proj_discount->theap.base, proj_discount->batCount, 5, 7);
  // auto pos_discount = select((int*)discount_rec->base, nRows, 5, 7);

  auto pages_disc = count_pages(pos, sizeof(lng));
  fprintf(stderr, "proj count = %lu, filter rate = (%lu/%lu) %.2f%%, numOfPages read = %lu\n", pos_discount->batCount, pos_discount->batCount, pos->batCount, 100.0*pos_discount->batCount/pos->batCount, pages_disc);

  std::string fname_quantity = db_path+l_quantity+".tail";
  auto quantity_rec = mapfile(fname_quantity.c_str());
  auto quantity_bat = maptoBAT(quantity_rec, TYPE_int, nRows);
  BAT* proj_pos_discount = BATproject(pos_discount, pos);
  BAT* proj_quantity = BATproject(proj_pos_discount, quantity_bat);
  auto pos_quantity = select<int>((int*)proj_quantity->theap.base, proj_quantity->batCount, INT_MIN, 23);
  // auto pos_quantity = select((int*)quantity_rec->base, nRows, 5, 7);
  auto pages_quantity = count_pages(proj_pos_discount, sizeof(int));

  fprintf(stderr, "proj count = %lu, filter rate = (%lu/%lu) %.2f%%, numOfPages read = %lu\n", pos_quantity->batCount, pos_quantity->batCount, pos_discount->batCount, 100.0*pos_quantity->batCount/pos_discount->batCount, pages_quantity);

  std::string fname_extendedprice = db_path+l_extendedprice+".tail";
  auto extendedprice_rec = mapfile(fname_extendedprice.c_str());
  auto extendedprice_bat = maptoBAT(extendedprice_rec, TYPE_lng, nRows);
  

  BAT* disc_price = merge<lng>((lng*)(extendedprice_rec->base), pos_quantity->batCount, BATproject(BATproject(pos_quantity, pos_discount),pos),
                               (lng*)(discount_rec->base), pos_quantity->batCount, BATproject(BATproject(pos_quantity, pos_discount),pos),
                               [](lng price, ulng disc) -> lng { return price*disc;});

  BAT* sum_revenue = NULL;
  auto stat = aggr_sum<lng,lng>((lng*)(disc_price->theap.base), pos_quantity->batCount, NULL, NULL, NULL, &sum_revenue);
  assert(stat == GDK_SUCCEED);

  fprintf(stderr, "revenvue = %.4lf\n", (((lng*)Tloc(sum_revenue,0))[0])/10000.0);

  
  BATclear(pos,0);
  unmapfile(extendedprice_rec);

  unmapfile(quantity_rec);

  unmapfile(date_rec);
  return 0;
}

