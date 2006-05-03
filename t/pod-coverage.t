#!perl -T

use Test::More;
eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;
#pod_coverage_ok("XML::MyXML", {also_private =>  [ qr/new/ ], }, "hi");
all_pod_coverage_ok({also_private =>  [ qr/./ ], }, "hi");
