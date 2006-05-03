#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'XML::MyXML' );
}

diag( "Testing XML::MyXML $XML::MyXML::VERSION, Perl $], $^X" );
