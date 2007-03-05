package XML::MyXML;

use strict;
use warnings;
use utf8;
use Carp;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml xml_to_simple check_xml);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);
=head1 NAME

XML::MyXML - A simple XML module

=head1 VERSION

Version 0.092

=cut

our $VERSION = '0.092';

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml xml_to_object);

    my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
    print tidy_xml($xml);

    my $obj = xml_to_object($xml);
    print "Price in Euros = " . $obj->path('price/eur')->value;

    $obj->simplify is hashref { item => { name => 'Table', price => { usd => '10.00', eur => '8.50' } } }
    $obj->simplify({ internal => 1 }) is hashref { name => 'Table', price => { usd => '10.00', eur => '8.50' } }

=head1 EXPORT

tidy_xml, xml_to_object, object_to_xml, simple_to_xml, xml_to_simple, check_xml

=head1 FUNCTIONS

=cut

sub _encode {
	my $string = shift;
	defined $string or $string = '';
	my %replace = 	(
					'<' => '&lt;', 
					'>' => '&gt;', 
					'&' => '&amp;',
					'\'' => '&apos;',
					'"' => '&quot;',
					);
	my $keys = "(".join("|", keys %replace).")";
	$string =~ s/$keys/$replace{$1}/g;
	return $string;
}

sub _decode {
	my $string = shift;
	defined $string or $string = '';
	$string =~ s/\&\#x([0-9a-f]+)\;/chr(hex($1))/eg;
	$string =~ s/\&\#([0-9]+)\;/chr($1)/eg;
	my %replace = 	(
					'<' => '&lt;', 
					'>' => '&gt;', 
					'&' => '&amp;',
					'\'' => '&apos;',
					'"' => '&quot;',
					);
	%replace = reverse %replace;
	my $keys = "(".join("|", keys %replace).")";
	$string =~ s/$keys/$replace{$1}/g;
	return $string;
}

sub _strip {
	my $string = shift;

	return defined $string ? ($string =~ /^\s*(.*?)\s*$/s)[0] : $string;
}

=head2 tidy_xml($raw_xml)

Returns the XML string in a tidy format (with tabs & newlines)

=cut


sub tidy_xml {
	my $xml = shift;
	if ($xml eq 'XML::MyXML') { $xml = shift; }
	my $flags = shift || {};

	my $object = &xml_to_object($xml);
	&_tidy_object($object, undef, $flags);
	return &object_to_xml($object);
}


=head2 xml_to_object($raw_xml)

Creates an 'XML::MyXML::Object' object from the raw XML provided

If called with the C<file> flag (like this: C<< xml_to_object($filename, { file => 1 }) >>), then the function's first parameter, instead of being an XML string, should be the path to a file that contains the XML document. If called with the C<soft> flag, the function will return C<undef> instead of dying (in case of error).

=cut

sub xml_to_object {
	my $xml = shift;
	if ($xml eq 'XML::MyXML') { $xml = shift; }
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	my $soft = $flags->{'soft'}; # soft = 'don't die if can't parse, just return undef'

	if ($flags->{'file'}) {
		open FILE, $xml or do { confess "Error: The file '$xml' could not be opened for reading." unless $soft; return undef; };
		$xml = join '', <FILE>;
		close FILE;
	}

	# Preprocess
	$xml =~ s/^(\s*<\?[^>]*\?>)*\s*//;
	# Parse CDATA sections
	$xml =~ s/<\!\[CDATA\[(.*?)\]\]>/&_encode($1)/egs;
	my @els = $xml =~ /(<!--.*?(?:-->|$)|<[^>]*?>|[^<>]+)/sg;
	# Remove comments and initial whitespace
	{
		my $init_ws = 1;
		foreach my $el (@els) {
			if ($el =~ /^<!--/) {
				if ($el !~ /-->$/) { confess "Error: unclosed XML comment block - '$el'" unless $soft; return undef; }
				undef $el;
				next;
			} elsif ($init_ws) {
				if ($el =~ /\S/) {
					$init_ws = 0;
				} else {
					undef $el;
				}
			}
		}
		@els = grep { defined $_ } @els;
		if (! @els) { confess "Error: No elements in XML document" unless $soft; return undef; }
	}
	my @stack;
	my $object = { content => [] };
	my $pointer = $object;
	foreach my $el (@els) {
		if ($el =~ /^<\?[^>]*\?>$/) {
			next;
		} elsif ($el =~ /^<\/?>$/) {
			confess "Error: Strange element: '$el'" unless $soft; return undef;
		} elsif ($el =~ /^<\/[^\s>]+>$/) {
			my ($element) = $el =~ /^<\/(\S+)>$/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; return undef; }
			if ($stack[$#stack]->{'element'} ne $element) { confess "Error: Incompatible stack element: stack='".$stack[$#stack]->{'element'}."' element='$el'" unless $soft; return undef; }
			my $stackentry = pop @stack;
			if ($#{$stackentry->{'content'}} == -1) {
				delete $stackentry->{'content'};
			}
			$pointer = $stackentry->{'parent'};
		} elsif ($el =~ /^<[^>]+\/>$/) {
			my ($element) = $el =~ /^<([^\s>\/]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; return undef; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/\/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $soft; return undef; }
				$attr{$name} = &_decode($value);
			}
			my $entry = { element => $element, attrs => \%attr, parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} elsif ($el =~ /^<[^\s>\/][^>]*>$/) {
			my ($element) = $el =~ /^<([^\s>]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; return undef; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $soft; return undef; }
				$attr{$name} = &_decode($value);
			}
			my $entry = { element => $element, attrs => \%attr, content => [], parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @stack, $entry;
			push @{$pointer->{'content'}}, $entry;
			$pointer = $entry;
		} elsif ($el =~ /^[^<>]*$/) {
			my $entry = { value => &_decode($el), parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} else {
			confess "Error: Strange element: '$el'" unless $soft; return undef;
		}
	}
	if (@stack) { confess "Error: some elements have not been closed in XML" unless $soft; return undef; }
	$object = $object->{'content'}[0];
	$object->{'parent'} = undef;
	return $object;
}

sub _objectarray_to_xml {
	my $object = shift;

	my $xml = '';
	foreach my $stuff (@$object) {
		if (! defined $stuff->{'element'} and defined $stuff->{'value'}) {
			$xml .= &_encode($stuff->{'value'});
		} else {
			$xml .= "<".$stuff->{'element'};
			foreach my $attrname (keys %{$stuff->{'attrs'}}) {
				$xml .= " ".$attrname.'="'.&_encode($stuff->{'attrs'}{$attrname}).'"';
			}
			if (! defined $stuff->{'content'}) {
				$xml .= "/>"
			} else {
				$xml .= ">";
				$xml .= &_objectarray_to_xml($stuff->{'content'});
				$xml .= "</".$stuff->{'element'}.">";
			}
		}
	}
	return $xml;
}

=head2 object_to_xml($object)

Creates an XML string from the 'XML::MyXML::Object' object provided

=cut

sub object_to_xml {
	my $object = shift;
	if ($object eq 'XML::MyXML') { $object = shift; }

#	my $xml = '';
#	$xml .= '<?xml version="1.1" encoding="utf-8"?>'."\n";
	#return $xml.&object_to_xml($object);
	return &_objectarray_to_xml([$object]);
}

sub _tidy_object {
	my $object = shift;
	my $tabs = shift || 0;
	my $flags = shift || {};

	if (! exists $flags->{'indentstring'}) { $flags->{'indentstring'} = "\t" }

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
		push @{$object->{'content'}}, { value => "\n".($flags->{'indentstring'}x($tabs+1)), parent => $object };
		push @{$object->{'content'}}, $children[$i];
	}
	push @{$object->{'content'}}, { value => "\n".($flags->{'indentstring'}x($tabs)), parent => $object };
	
	for my $i (0..$#{$object->{'content'}}) {
		&_tidy_object($object->{'content'}[$i], $tabs+1, $flags);
	}
}


=head2 simple_to_xml($simple_array_ref)

Produces a raw XML string from either an array reference, a hash reference or a mixed structure such as these examples:

    { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } }
    [ thing => [ name => 'John', location => [ city => 'New York', country => 'U.S.A.' ] ] ]
    { thing => { name => 'John', location => [ city => 'New York', city => 'Boston', country => 'U.S.A.' ] } }

=cut

sub simple_to_xml {
	my $arref = shift;
	if ($arref eq 'XML::MyXML') { $arref = shift; }

	my $xml = '';
	my ($key, $value, @residue) = (ref $arref eq 'HASH') ? %$arref : @$arref;
	if (@residue) { confess "Error: the provided simple ref contains more than 1 top element"; }
	my ($tag) = $key =~ /^(\S+)/g;
	confess "Error: Strange key: $key" if ! defined $tag;

	if (! ref $value) {
		$xml .= "<$key>"._encode($value)."</$key>";
	} else {
		$xml .= "<$key>"._arrayref_to_xml($value)."</$key>";
	}
	return $xml;
}


sub _arrayref_to_xml {
	my $arref = shift;

	my $xml = '';

	if (ref $arref eq 'HASH') { return _hashref_to_xml($arref); }

	while (@$arref) {
		my $key = shift @$arref;
		my ($tag) = $key =~ /^(\S+)/g;
		confess "Error: Strange key: $key" if ! defined $tag;
		my $value = shift @$arref;

		if (! ref $value) {
			$xml .= "<$key>"._encode($value)."</$tag>";
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value)."</$tag>";
		}
	}
	return $xml;
}


sub _hashref_to_xml {
	my $hashref = shift;

	my $xml = '';

	while (my ($key, $value) = each %$hashref) {
		my ($tag) = $key =~ /^(\S+)/g;
		confess "Error: Strange key: $key" if ! defined $tag;

		if (! ref $value) {
			$xml .= "<$key>"._encode($value)."</$tag>";
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value)."</$tag>";
		}
	}
	return $xml;
}

=head2 xml_to_simple($raw_xml)

Produces a very simple hash object from the raw XML string provided. An example hash object created thusly is this: S<C<< { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } } >>>

Since the object created is a hashref, duplicate keys will be discarded. WARNING: This function only works on very simple XML strings, i.e. children of an element may not consist of both text and elements (child elements will be discarded in that case)

You can use flags like this: S<C<< &xml_to_simple($raw_xml, {strip => 1, internal => 1, ...}) >>>.

If called with the 'C<internal>' flag, then the hashref returned will be the first value of the hashref that would otherwise be returned, i.e. a hashref created only by the contents of the top element in the XML and which doesn't contain information about the top-level tag (See L</SYNOPSIS> section for an example)

If called with the 'C<strip>' flag, all text contents will be stripped of possible beginning and/or ending whitespace.

If called with the 'C<file>' flag, then the function's first parameter should be the path to an XML file, instead of being an XML string.

If called with the 'C<soft>' flag, the function will return undef instead of dying (in case of error)

=cut

sub xml_to_simple {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	my $object = &xml_to_object($xml, $flags);

	return defined $object ? $object->simplify($flags) : $object;
}

sub _objectarray_to_simple {
	my $object = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	if (! defined $object) { return undef; }

	my $hashref = {};

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			$hashref->{ $stuff->{'element'} } = &_objectarray_to_simple($stuff->{'content'}, $flags);
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			if ($flags->{'strip'}) { $value = &XML::MyXML::_strip($value); }
			return $value if $value =~ /\S/;
		}
	}

	if (keys %$hashref) {
		return $hashref;
	} else {
		return undef;
	}
}


=head2 check_xml($raw_xml)

Returns 1 if the $raw_xml string is valid XML (valid enough to be used by this module), and 0 otherwise. Can be used with the C<file> flag. (See L<xml_to_simple|/xml_to_simple($raw_xml)> for meaning and example of this flag)

=cut

sub check_xml {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	return 1 if &xml_to_object($xml, { %$flags, soft => 1 }); # soft = 'don't die if can't parse, just return undef'
	return 0;
}



package XML::MyXML::Object;

use Carp;

=head1 OBJECT METHODS

=cut

sub new {
	my $class = shift;
	my $xml = shift;

	my $obj = XML::MyXML::xml_to_object($xml);
	bless $obj, $class;
	return $obj;
}

sub children {
	my $self = shift;
	my $tag = shift;

	my $tagmeta = defined $tag ? quotemeta($tag) : '';

	if (defined $tag) {
		return grep {defined $_->{'element'} and ($_->{'element'} eq $tag or $_->{'element'} =~ /\:$tagmeta$/)} @{$self->{'content'}};
	} else {
		return grep { defined $_->{'element'} } @{$self->{'content'}};
	}
}

=head2 $obj->path("subtag1/subsubtag2/.../subsubsubtagX")

Returns the element specified by the path as an XML::MyXML::Object object. When there are more than one tags with the specified name in the last step of the path, it will return all of them as an array. In scalar context will only return the first one.

=cut

sub path {
	my $self = shift;
	my $path = shift;

	my @path = split /\//, $path;
	my $el = $self;
	for (my $i = 0; $i < $#path; $i++) {
		my $pathstep = $path[$i];
		($el) = $el->children($pathstep);
		if (! defined $el) { return; }
	}
	return wantarray ? $el->children($path[$#path]) : ($el->children($path[$#path]))[0];
}

=head2 $obj->value

When the element represented by the $obj object has only text contents, returns those contents as a string. If the $obj element has no contents, value will return an empty string.

Can be used with the C<strip> flag (as in: S<C<< $obj->value({ strip => 1 }) >>>) to strip possible whitespace in the beginning and end of the value.

=cut

sub value {
	my $self = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	my $value = &XML::MyXML::_decode($self->{'content'}[0]{'value'});
	if ($flags->{'strip'}) { $value = &XML::MyXML::_strip($value); }
	return $value;
}

=head2 $obj->attr('attrname')

Returns the value of the 'attrname' attribute of top element. Returns undef if attribute does not exist.

=cut

sub attr {
	my $self = shift;
	my $attrname = shift;

	return $self->{'attrs'}->{$attrname};
}

=head2 $obj->tag

Returns the tag of the $obj element (after stripping it from namespaces). E.g. if $obj represents an <rss:item> element, C<< $obj->tag >> will just return the name iitem'.
Returns undef if $obj doesn't represent a tag.

=cut

sub tag {
	my $self = shift;

	my $tag = $self->{'element'};
	if (defined $tag) {
		$tag =~ s/^.*\://;
		return $tag;
	} else {
		return undef;
	}
}

=head2 $obj->simplify

Returns a very simple hashref, like the one returned with &XML::MyXML::xml_to_simple. Same restrictions and warnings apply. May be called with the C<internal> and/or C<strip> flags (for more on these flags, see this documentation on the L<xml_to_simple|/xml_to_simple($raw_xml)> function)

=cut

sub simplify {
	my $self = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	my $simple = &XML::MyXML::_objectarray_to_simple([$self], $flags);
	if (! $flags->{'internal'}) { return $simple } else { return (values %$simple)[0] }
}

=head2 $obj->to_xml

Returns the XML string of the object, just like calling C<&object_to_xml( $obj )>

=cut

sub to_xml {
	my $self = shift;
	
	return XML::MyXML::object_to_xml($self);
}

=head2 $obj->to_tidy_xml

Returns the XML string of the object in tidy form, just like calling C<&tidy_xml( &object_to_xml( $obj ) )>

=cut

sub to_tidy_xml {
	my $self = shift;
	
	my $xml = XML::MyXML::object_to_xml($self);
	return XML::MyXML::tidy_xml($xml);
}


=head1 AUTHOR

Alexander Karelas, C<< <karjala at karjala.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-xml-myxml at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=XML-MyXML>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc XML::MyXML

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/XML-MyXML>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/XML-MyXML>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=XML-MyXML>

=item * Search CPAN

L<http://search.cpan.org/dist/XML-MyXML>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Alexander Karelas, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of XML::MyXML
