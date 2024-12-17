#include "driver.h"

int main(int argc, const char **argv) {
  if (argc < 2) {
    saplang::Driver::display_help();
    return 1;
  }
  saplang::Driver driver{argc, argv};
  return driver.run(std::cout);
}
