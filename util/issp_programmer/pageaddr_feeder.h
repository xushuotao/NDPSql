#ifndef __PAGEADDR_FEEDER__
#define __PAGEADDR_FEEDER__

#include "GeneratedTypes.h"
#include "PageFeeder.h"

#include "issp_programmer.h"
#include "flashmanage.h"


class PageAddrFeeder{
public:
	PageAddrFeeder();
	~PageAddrFeeder();
    int sendTableTask(TableTask* task, FlashManager* flash_manger, bool *doneSending, size_t &totalBytes);
private:
    static bool devInit;
    static PageFeederProxy* page_feeder;
	static int sendToFPGA(uint8_t colId, uint32_t pageAddr, bool last);
	static void *sender_thread(void* arg);
};

#endif
