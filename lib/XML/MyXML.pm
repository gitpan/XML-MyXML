package XML::MyXML;
{
  $XML::MyXML::VERSION = '0.9000';
}
# ABSTRACT: A simple-to-use XML module, for parsing and creating XML documents

use strict;
use warnings;
use Carp;
use Scalar::Util qw( weaken );
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml xml_to_simple check_xml xml_escape);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);
use Encode;


sub _encode {
	my $string = shift;
	my $entities = shift || {};
	defined $string or $string = '';
	my %replace = 	(
					'<' => '&lt;',
					'>' => '&gt;',
					'&' => '&amp;',
					'\'' => '&apos;',
					'"' => '&quot;',
					);
	my $keys = "(".join("|", sort {length($b) <=> length($a)} keys %replace).")";
	$string =~ s/$keys/$replace{$1}/g;
	return $string;
}


sub xml_escape {
	my ($string) = @_;

	return _encode($string);
}

sub _decode {
	my $string = shift;
	my $entities = shift || {};
	my $flags = shift || {};
	defined $string or $string = '';
	my %replace = reverse (
					(reverse (%$entities)),
					'<' => '&lt;',
					'>' => '&gt;',
					'&' => '&amp;',
					'\'' => '&apos;',
					'"' => '&quot;',
	);
	my @capture = map "\Q$_\E", keys %replace;
	push @capture, '&#x[0-9A-Fa-f]+;', '&#[0-9]+;';
	my $capture = "(".join("|", @capture).")";
	my @captured = $string =~ /$capture/g;
	@captured	or return $string;
	my %conv;
	foreach my $e (@captured) {
		if (exists $conv{$e}) { next; }
		if (exists $replace{$e}) {
			$conv{$e} = $replace{$e};
		} elsif ($e =~ /^&#x([0-9a-fA-F]+);$/) {
			$conv{$e} = chr(hex($1));
		} elsif ($e =~ /^&#([0-9]+);$/) {
			$conv{$e} = chr($1);
		}
	}
	my $keys = "(".join("|", map "\Q$_\E", keys %conv).")";
	$string =~ s/$keys/$conv{$1}/g;
	return $string;
}

sub _strip {
	my $string = shift;

	# NOTE: Replace this with the 'r' flag of the substitution operator
	return defined $string ? ($string =~ /^\s*(.*?)\s*$/s)[0] : $string;
}

sub _strip_ns {
	my $string = shift;

	# NOTE: Replace this with the 'r' flag of the substitution operator
	return defined $string ? ($string =~ /^(?:.+\:)?(.*)$/s)[0] : $string;
}



sub tidy_xml {
	my $xml = shift;
	my $flags = shift || {};

	my $object = xml_to_object($xml, $flags);
	defined $object or return $object;
	_tidy_object($object, undef, $flags);
	my $return = $object->to_xml({ %$flags, tidy => 0 }) . "\n";
	return $return;
}



sub xml_to_object {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if ($flags->{'file'}) {
		open my $fh, '<', $xml	or confess "Error: The file '$xml' could not be opened for reading: $!";
		$xml = join '', <$fh>;
		close $fh;
	}

	my (undef, undef, $encoding) = $xml =~ /<\?xml(\s[^>]+)?\sencoding=(['"])(.*?)\2/g;
	$encoding = 'UTF-8'		if ! defined $encoding;
	if ($encoding =~ /^utf-?8$/i) { $encoding = 'UTF-8'; }
	eval {
		$xml = decode($encoding, $xml, Encode::FB_CROAK);
	};
	! $@	or confess 'Error: Input string is invalid UTF-8';

	my $entities = {};

	# Parse CDATA sections
	$xml =~ s/<\!\[CDATA\[(.*?)\]\]>/_encode($1)/egs;
	my @els = $xml =~ /(<!--.*?(?:-->|$)|<[^>]*?>|[^<>]+)/sg;
	# Remove comments, special markup and initial whitespace
	{
		my $init_ws = 1;
		foreach my $el (@els) {
			if ($el =~ /^<!--/) {
				if ($el !~ /-->$/) { confess encode_utf8("Error: unclosed XML comment block - '$el'"); }
				undef $el;
			} elsif ($el =~ /^<\?/) { # like <?xml?> or <?target?>
				if ($el !~ /\?>$/) { confess encode_utf8("Error: Erroneous special markup - '$el'"); }
				undef $el;
			} elsif (my ($entname, undef, $entvalue) = $el =~ /^<!ENTITY\s+(\S+)\s+(['"])(.*?)\2\s*>$/g) {
				$entities->{"&$entname;"} = _decode($entvalue);
				undef $el;
			} elsif ($el =~ /<!/) { # like <!DOCTYPE> or <!ELEMENT> or <!ATTLIST>
				undef $el;
			} elsif ($init_ws) {
				if ($el =~ /\S/) {
					$init_ws = 0;
				} else {
					undef $el;
				}
			}
		}
		@els = grep { defined $_ } @els;
		if (! @els) { confess "Error: No elements in XML document"; }
	}
	my @stack;
	my $object = bless ({ content => [] }, 'XML::MyXML::Object');
	my $pointer = $object;
	foreach my $el (@els) {
		if ($el =~ /^<\/?>$/) {
			confess encode_utf8("Error: Strange element: '$el'");
		} elsif ($el =~ /^<\/[^\s>]+>$/) {
			my ($element) = $el =~ /^<\/(\S+)>$/g;
			if (! length($element)) { confess encode_utf8("Error: Strange element: '$el'"); }
			if ($stack[-1]{'element'} ne $element) { confess encode_utf8("Error: Incompatible stack element: stack='".$stack[-1]{'element'}."' element='$el'"); }
			my $stackentry = pop @stack;
			if ($#{$stackentry->{'content'}} == -1) {
				delete $stackentry->{'content'};
			}
			$pointer = $stackentry->{'parent'};
		} elsif ($el =~ /^<[^>]+\/>$/) {
			my ($element) = $el =~ /^<([^\s>\/]+)/g;
			if (! length($element)) { confess encode_utf8("Error: Strange element: '$el'"); }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/\/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess encode_utf8("Error: Strange attribute: '$attr'"); }
				$attr{$name} = _decode($value, $entities);
			}
			my $entry = { element => $element, attrs => \%attr, parent => $pointer };
			weaken( $entry->{'parent'} );
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} elsif ($el =~ /^<[^\s>\/][^>]*>$/) {
			my ($element) = $el =~ /^<([^\s>]+)/g;
			if (! length($element)) { confess encode_utf8("Error: Strange element: '$el'"); }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess encode_utf8("Error: Strange attribute: '$attr'"); }
				$attr{$name} = _decode($value, $entities);
			}
			my $entry = { element => $element, attrs => \%attr, content => [], parent => $pointer };
			weaken( $entry->{'parent'} );
			bless $entry, 'XML::MyXML::Object';
			push @stack, $entry;
			push @{$pointer->{'content'}}, $entry;
			$pointer = $entry;
		} elsif ($el =~ /^[^<>]*$/) {
			my $entry = { value => _decode($el, $entities), parent => $pointer };
			weaken( $entry->{'parent'} );
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} else {
			confess encode_utf8("Error: Strange element: '$el'");
		}
	}
	if (@stack) { confess encode_utf8("Error: The <$stack[-1]{'element'}> element has not been closed in XML"); }
	$object = $object->{'content'}[0];
	$object->{'parent'} = undef;
	return $object;
}

sub _objectarray_to_xml {
	my $object = shift;

	my $xml = '';
	foreach my $stuff (@$object) {
		if (! defined $stuff->{'element'} and defined $stuff->{'value'}) {
			$xml .= _encode($stuff->{'value'});
		} else {
			$xml .= "<".$stuff->{'element'};
			foreach my $attrname (keys %{$stuff->{'attrs'}}) {
				$xml .= " ".$attrname.'="'._encode($stuff->{'attrs'}{$attrname}).'"';
			}
			if (! defined $stuff->{'content'}) {
				$xml .= "/>"
			} else {
				$xml .= ">";
				$xml .= _objectarray_to_xml($stuff->{'content'});
				$xml .= "</".$stuff->{'element'}.">";
			}
		}
	}
	return $xml;
}


sub object_to_xml {
	my $object = shift;
	my $flags = shift || {};

	return $object->to_xml( $flags );
}

sub _tidy_object {
	my $object = shift;
	my $tabs = shift || 0;
	my $flags = shift || {};

	$flags->{'indentstring'} = "\t" unless exists $flags->{'indentstring'};

	if (! defined $object->{'content'} or ! @{$object->{'content'}}) { return; }
	my $hastext;
	my @children = @{$object->{'content'}};
	foreach my $i (0..$#children) {
		my $child = $children[$i];
		if (defined $child->{'value'}) {
			if ($child->{'value'} =~ /\S/) {
				$hastext = 1;
				last;
			}
		}
	}
	if ($hastext) { return; }

	@{$object->{'content'}} = grep { ! defined $_->{'value'} or $_->{'value'} !~ /^\s*$/ } @{$object->{'content'}};

	@children = @{$object->{'content'}};
	$object->{'content'} = [];
	for my $i (0..$#children) {
		my $whitespace = bless ({ value => "\n".($flags->{'indentstring'}x($tabs+1)), parent => $object }, 'XML::MyXML::Object');
		weaken( $whitespace->{'parent'} );
		push @{$object->{'content'}}, $whitespace;
		push @{$object->{'content'}}, $children[$i];
	}
	my $whitespace = bless ({ value => "\n".($flags->{'indentstring'}x($tabs)), parent => $object }, 'XML::MyXML::Object');
	weaken( $whitespace->{'parent'} );
	push @{$object->{'content'}}, $whitespace;

	for my $i (0..$#{$object->{'content'}}) {
		_tidy_object($object->{'content'}[$i], $tabs+1, $flags);
	}
}



sub simple_to_xml {
	my $arref = shift;
	my $flags = shift || {};

	my $xml = '';
	my ($key, $value, @residue) = (ref $arref eq 'HASH') ? %$arref : @$arref;
	if (@residue) { confess "Error: the provided simple ref contains more than 1 top element"; }
	my ($tag) = $key =~ /^(\S+)/g;
	confess encode_utf8("Error: Strange key: $key") if ! defined $tag;

	if (! ref $value) {
		if (defined $value and length $value) {
			$xml .= "<$key>"._encode($value)."</$tag>";
		} else {
			$xml .= "<$key/>";
		}
	} else {
		$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
	}
	if ($flags->{'tidy'}) { $xml = tidy_xml($xml, { $flags->{'indentstring'} ? (indentstring => $flags->{'indentstring'}) : () }); }
	my $decl = $flags->{'complete'} ? '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'."\n" : '';
	$decl .= "<?xml-stylesheet type=\"text/xsl\" href=\"$flags->{'xslt'}\"?>\n" if $flags->{'xslt'};
	$xml = $decl . $xml;

	if (defined $flags->{'save'}) {
		open my $fh, '>', $flags->{'save'} or confess "Error: Couldn't open file '$flags->{'save'}' for writing: $!";
		binmode $fh, ':encoding(UTF-8)';
		print $fh $xml;
		close $fh;
	}

	return encode_utf8( $xml );
}


sub _arrayref_to_xml {
	my $arref = shift;
	my $flags = shift || {};

	my $xml = '';

	if (ref $arref eq 'HASH') { return _hashref_to_xml($arref, $flags); }

	foreach (my $i = 0; $i <= $#$arref; ) {
	#while (@$arref) {
		my $key = $arref->[$i++];
		#my $key = shift @$arref;
		my ($tag) = $key =~ /^(\S+)/g;
		confess encode_utf8("Error: Strange key: $key") if ! defined $tag;
		my $value = $arref->[$i++];
		#my $value = shift @$arref;

		if ($key eq '!as_is') {
			$xml .= $value if check_xml($value);
		} elsif (! ref $value) {
			if (defined $value and length $value) {
				$xml .= "<$key>"._encode($value)."</$tag>";
			} else {
				$xml .= "<$key/>";
			}
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
		}
	}
	return $xml;
}


sub _hashref_to_xml {
	my $hashref = shift;
	my $flags = shift || {};

	my $xml = '';

	while (my ($key, $value) = each %$hashref) {
		my ($tag) = $key =~ /^(\S+)/g;
		confess encode_utf8("Error: Strange key: $key") if ! defined $tag;

		if ($key eq '!as_is') {
			$xml .= $value if check_xml($value);
		} elsif (! ref $value) {
			if (defined $value and length $value) {
				$xml .= "<$key>"._encode($value)."</$tag>";
			} else {
				$xml .= "<$key/>";
			}
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
		}
	}
	return $xml;
}


sub xml_to_simple {
	my $xml = shift;
	my $flags = shift || {};

	my $object = xml_to_object($xml, $flags);

	my $return = defined $object ? $object->simplify($flags) : $object;

	return $return;
}

sub _objectarray_to_simple {
	my $object = shift;
	my $flags = shift || {};

	if (! defined $object) { return undef; }

	if ($flags->{'arrayref'}) {
		return _objectarray_to_simple_arrayref($object, $flags);
	} else {
		return _objectarray_to_simple_hashref($object, $flags);
	}
}

sub _objectarray_to_simple_hashref {
	my $object = shift;
	my $flags = shift || {};

	if (! defined $object) { return undef; }

	my $hashref = {};

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			my $key = $stuff->{'element'};
			if ($flags->{'strip_ns'}) { $key = _strip_ns($key); }
			$hashref->{ $key } = _objectarray_to_simple($stuff->{'content'}, $flags);
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			if ($flags->{'strip'}) { $value = _strip($value); }
			return $value if $value =~ /\S/;
		}
	}

	if (keys %$hashref) {
		return $hashref;
	} else {
		return undef;
	}
}

sub _objectarray_to_simple_arrayref {
	my $object = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (! defined $object) { return undef; }

	my $arrayref = [];

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			my $key = $stuff->{'element'};
			if ($flags->{'strip_ns'}) { $key = _strip_ns($key); }
			push @$arrayref, ( $key, _objectarray_to_simple($stuff->{'content'}, $flags) );
			#$hashref->{ $key } = _objectarray_to_simple($stuff->{'content'}, $flags);
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			if ($flags->{'strip'}) { $value = _strip($value); }
			return $value if $value =~ /\S/;
		}
	}

	if (@$arrayref) {
		return $arrayref;
	} else {
		return undef;
	}
}



sub check_xml {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	my $obj = eval { xml_to_object($xml, $flags) };
	return ! $@;
}



package XML::MyXML::Object;
{
  $XML::MyXML::Object::VERSION = '0.9000';
}

use Carp;
use Encode;


sub new {
	my $class = shift;
	my $xml = shift;

	my $obj = XML::MyXML::xml_to_object($xml);
	bless $obj, $class;
	return $obj;
}

sub _parse_description {
	my ($desc) = @_;

	my ($tag, $attrs_str) = $desc =~ /^([^\[]*)(.*)$/g;
	my %attrs = $attrs_str =~ /\[([^=\]]+)(?:=([^\]]*))?\]/g;

	return ($tag, \%attrs);
}

sub cmp_element {
	my ($self, $desc) = @_;

	my ($tag, $attrs) = ref $desc
			? @$desc{qw/ tag attrs /}
			: _parse_description($desc);

	! length $tag or $self->{'element'} =~ /(^|\:)\Q$tag\E$/	or return 0;
	foreach my $attr (keys %$attrs) {
		my $val = $self->attr($attr);
		defined $val											or return 0;
		! defined $attrs->{$attr} or $attrs->{$attr} eq $val	or return 0;
	}

	return 1;
}

sub children {
	my $self = shift;
	my $tag = shift;

	$tag = '' if ! defined $tag;

	my @all_children = grep { defined $_->{'element'} } @{$self->{'content'}};
	length $tag		or return @all_children;

	($tag, my $attrs) = _parse_description($tag);
	my $desc = { tag => $tag, attrs => $attrs };

	my @results;
	CHILD: foreach my $child (@all_children) {
		$child->cmp_element($desc)		or next;
		push @results, $child;
	}

	return @results;
}

sub parent {
	my $self = shift;

	return $self->{'parent'};
}


sub path {
	my $self = shift;
	my $path = shift;

	my @path;
	my $orig_path = $path;
	$path = "/" . $path;
	while (length $path) {
		my $success = $path =~ s!^/((?:[^/\[]*)?(?:\[[^\]]+\])*)!!;
		my $seg = $1;
		if ($success) {
			push @path, $seg;
		} else {
			die "Invalid path: $orig_path";
		}
	}

	my $el = $self;
	for (my $i = 0; $i < $#path; $i++) {
		my $pathstep = $path[$i];
		($el) = $el->children($pathstep);
		if (! defined $el) { return; }
	}
	return wantarray ? $el->children($path[$#path]) : ($el->children($path[$#path]))[0];
}


sub value {
	my $self = shift;
	my $flags = shift || {};

	if ($self->{'content'} and $self->{'content'}[0]) {
		my $value = $self->{'content'}[0]{'value'};
		if ($flags->{'strip'}) { $value = XML::MyXML::_strip($value); }
		return $value;
	} else {
		return undef;
	}
}


sub attr {
	my $self = shift;
	my $attrname = shift;
	my ($set_to, $must_set, $flags);
	if (@_) {
		my $next = shift;
		if (! ref $next) {
			$set_to = $next;
			$must_set = 1;
			$flags = shift;
		} else {
			$flags = $next;
		}
	}
	$flags ||= {};

	if (defined $attrname) {
		if ($must_set) {
			if (defined ($set_to)) {
				$self->{'attrs'}{$attrname} = $set_to;
				return $set_to;
			} else {
				delete $self->{'attrs'}{$attrname};
				return;
			}
		} else {
			my $attrvalue = $self->{'attrs'}->{$attrname};
			return $attrvalue;
		}
	} else {
		return %{$self->{'attrs'}};
	}
}


sub tag {
	my $self = shift;
	my $flags = shift || {};

	my $tag = $self->{'element'};
	if (defined $tag) {
		$tag =~ s/^.*\://	if $flags->{'strip_ns'};
		return $tag;
	} else {
		return undef;
	}
}


sub simplify {
	my $self = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	my $simple = XML::MyXML::_objectarray_to_simple([$self], $flags);
	if (! $flags->{'internal'}) {
		return $simple;
	} else {
		if (ref $simple eq 'HASH') {
			return (values %$simple)[0];
		} elsif (ref $simple eq 'ARRAY') {
			return $simple->[1];
		}
	}
}


sub to_xml {
	my $self = shift;
	my $flags = shift || {};

	my $decl = $flags->{'complete'} ? '<?xml version="1.1" encoding="UTF-8" standalone="yes" ?>'."\n" : '';
	my $xml = encode_utf8( XML::MyXML::_objectarray_to_xml([$self]) );
	if ($flags->{'tidy'}) { $xml = XML::MyXML::tidy_xml($xml, { %$flags, complete => 0, save => undef }); }
	$xml = $decl . $xml;
	if (defined $flags->{'save'}) {
		open my $fh, '>', $flags->{'save'} or confess "Error: Couldn't open file '$flags->{'save'}' for writing: $!";
		print $fh $xml;
		close $fh;
	}
	return $xml;
}


sub to_tidy_xml {
	my $self = shift;
	my $flags = shift || {};

	$flags->{'tidy'} = 1;
	return $self->to_xml( $flags );
}





1; # End of XML::MyXML

__END__

=pod

=head1 NAME

XML::MyXML - A simple-to-use XML module, for parsing and creating XML documents

=head1 VERSION

version 0.9000

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml xml_to_object);
    use XML::MyXML qw(:all);

    my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
    print tidy_xml($xml);

    my $obj = xml_to_object($xml);
    print "Price in Euros = " . $obj->path('price/eur')->value;

    $obj->simplify is hashref { item => { name => 'Table', price => { usd => '10.00', eur => '8.50' } } }
    $obj->simplify({ internal => 1 }) is hashref { name => 'Table', price => { usd => '10.00', eur => '8.50' } }

=head1 EXPORT

tidy_xml, xml_to_object, object_to_xml, simple_to_xml, xml_to_simple, check_xml

=head1 FEATURES & LIMITATIONS

This module can parse XML comments, CDATA sections, XML entities (the standard five and numeric ones) and simple non-recursive C<< <!ENTITY> >>s

It will ignore (won't parse) C<< <!DOCTYPE...> >>, C<< <?...?> >> and other C<< <!...> >> special markup

XML documents passed as parameters to this module's functions must be strings containing bytes/octets, rather than contain characters. They also must be UTF-8 encoded unless an encoding is declared in the initial XML declaration <?xml ... ?> of the document. All XML documents produced by this module will be UTF-8 encoded (bytes/octets). However all other strings which are output by this module's functions and methods (and which are not XML documents) will contain characters rather than bytes/octets.

XML documents to be parsed may not contain the C<< > >> character unencoded in attribute values

=head1 OPTIONAL FUNCTION FLAGS

Some functions and methods in this module accept optional flags, listed under each function in the documentation. They are optional, default to zero unless stated otherwise, and can be used as follows: S<C<< function_name( $param1, { flag1 => 1, flag2 => 1 } ) >>>. This is what each flag does:

C<strip> : the function will strip initial and ending whitespace from all text values returned

C<file> : the function will expect the path to a file containing an XML document to parse, instead of an XML string

C<complete> : the function's XML output will include an XML declaration (C<< <?xml ... ?>  >>) in the beginning

C<internal> : the function will only return the contents of an element in a hashref instead of the element itself (see L</SYNOPSIS> for example)

C<tidy> : the function will return tidy XML

C<indentstring> : when producing tidy XML, this denotes the string with which child elements will be indented (Default is the 'tab' character)

C<save> : the function (apart from doing what it's supposed to do) will also save its XML output in a file whose path is denoted by this flag

C<strip_ns> : strip the namespaces (characters up to and including ':') from the tags

C<xslt> : will add a <?xml-stylesheet?> link in the XML that's being output, of type 'text/xsl', pointing to the filename or URL denoted by this flag

C<arrayref> : the function will create a simple arrayref instead of a simple hashref (which will preserve order and elements with duplicate tags)

=head1 FUNCTIONS

=head2 xml_escape($string)

Returns the same string, but with the C<< < >>, C<< > >>, C<< & >>, C<< " >> and C<< ' >> characters replaced by their XML entities (e.g. C<< &amp; >>).

=head2 tidy_xml($raw_xml)

Returns the XML string in a tidy format (with tabs & newlines)

Optional flags: C<file>, C<complete>, C<indentstring>, C<save>

=head2 xml_to_object($raw_xml)

Creates an 'XML::MyXML::Object' object from the raw XML provided

Optional flags: C<file>

=head2 object_to_xml($object)

Creates an XML string from the 'XML::MyXML::Object' object provided

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>

=head2 simple_to_xml($simple_array_ref)

Produces a raw XML string from either an array reference, a hash reference or a mixed structure such as these examples:

    { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } }
    [ thing => [ name => 'John', location => [ city => 'New York', country => 'U.S.A.' ] ] ]
    { thing => { name => 'John', location => [ city => 'New York', city => 'Boston', country => 'U.S.A.' ] } }

All the strings in C<$simple_array_ref> need to contain characters, rather than bytes/octets. The XML output of this function however will be a UTF-8 encoded string (i.e. will contain bytes/octets).

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<xslt>

=head2 xml_to_simple($raw_xml)

Produces a very simple hash object from the raw XML string provided. An example hash object created thusly is this: S<C<< { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } } >>>

Since the object created is a hashref, duplicate keys will be discarded. WARNING: This function only works on very simple XML strings, i.e. children of an element may not consist of both text and elements (child elements will be discarded in that case)

All strings contained in the output simple structure, will contain characters rather than octets/bytes.

Optional flags: C<internal>, C<strip>, C<file>, C<strip_ns>, C<arrayref>

=head2 check_xml($raw_xml)

Returns true if the $raw_xml string is valid XML (valid enough to be used by this module), and false otherwise.

Optional flags: C<file>

=head1 OBJECT METHODS

=head2 $obj->path("subtag1/subsubtag2[attr1=val1][attr2]/.../subsubsubtagX")

Returns the element specified by the path as an XML::MyXML::Object object. When there are more than one tags with the specified name in the last step of the path, it will return all of them as an array. In scalar context will only return the first one. CSS3-style attribute selectors are allowed in the path next to the tagnames, for example: C<< p[class=big] >> will only return C<< <p> >> elements that contain an attribute called "class" with a value of "big". p[class] on the other hand will return p elements having a "class" attribute, but that attribute can have any value.

=head2 $obj->value

When the element represented by the $obj object has only text contents, returns those contents as a string. If the $obj element has no contents, value will return an empty string.

Optional flags: C<strip>

=head2 $obj->attr('attrname' [, 'attrvalue'])

Gets/Sets the value of the 'attrname' attribute of the top element. Returns undef if attribute does not exist. If called without the 'attrname' paramter, returns a hash with all attribute => value pairs. If setting with an attrvalue of C<undef>, then removes that attribute entirely.

Input parameters and output are all in character strings, rather than octets/bytes.

Optional flags: none

=head2 $obj->tag

Returns the tag of the $obj element. E.g. if $obj represents an <rss:item> element, C<< $obj->tag >> will return the string 'rss:item'.
Returns undef if $obj doesn't represent a tag.

Optional flags: C<strip_ns>

=head2 $obj->simplify

Returns a very simple hashref, like the one returned with C<&XML::MyXML::xml_to_simple>. Same restrictions and warnings apply.

Optional flags: C<internal>, C<strip>, C<strip_ns>, C<arrayref>

=head2 $obj->to_xml

Returns the XML string of the object, just like calling C<object_to_xml( $obj )>

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>

=head2 $obj->to_tidy_xml

Returns the XML string of the object in tidy form, just like calling C<tidy_xml( object_to_xml( $obj ) )>

Optional flags: C<complete>, C<indentstring>, C<save>

=head1 BUGS

If you have a Github account, report your issues at
L<https://github.com/akarelas/xml-myxml/issues>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

Alexander Karelas <karjala@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Alexander Karelas.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
