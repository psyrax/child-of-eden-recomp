// eden - ReXGlue Recompiled Project

#include <rex/app/title_app.h>

#include "generated/default/eden_init.h"

class EdenApp : public rex::app::TitleApp {
 public:
  EdenApp() : TitleApp("eden", kPPCImageConfig) {}
};

REX_TITLE_APP(EdenApp)
