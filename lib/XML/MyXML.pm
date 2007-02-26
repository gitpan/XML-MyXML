package XML::MyXML;

use strict;
use warnings;
use utf8;
use Carp;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml xml_to_simple check_xml);

=head1 NAME

XML::MyXML - A simple XML module

=head1 VERSION

Version 0.076

=cut

our $VERSION = '0.076';

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml xml_to_object);

    my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
    print tidy_xml($xml);

    my $obj = xml_to_object($xml);
    print "Price in Euros = " . $obj->path('price/eur')->value;

    $obj->simplify is hashref { item => { name => 'Table', price => { usd => '10.00', eur => '8.50' } } }

=head1 EXPORT

tidy_xml, object_to_xml, xml_to_object, simple_to_xml, xml_to_simple

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


=head2 tidy_xml($raw_xml)

Returns the XML string in a tidy format (with tabs & newlines)

=cut


sub tidy_xml {
	my $xml = shift;
	if ($xml eq 'XML::MyXML') { $xml = shift; }

	my $object = &xml_to_object($xml);
	&_tidy_object($object);
	return &object_to_xml($object);
}


=head2 xml_to_object($raw_xml)

Creates an 'XML::MyXML::Object' object from the raw XML provided

=cut

sub xml_to_object {
	my $xml = shift;
	my $jk = shift; # just checking xml
	if ($xml eq 'XML::MyXML') { $xml = shift; }

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
				if ($el !~ /-->$/) { confess "Error: unclosed XML comment block - '$el'" unless $jk; return 0; }
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
		if (! @els) { confess "Error: No elements in XML document" unless $jk; return 0; }
	}
	my @stack;
	my $object = { content => [] };
	my $pointer = $object;
	foreach my $el (@els) {
		if ($el =~ /^<\?[^>]*\?>$/) {
			next;
		} elsif ($el =~ /^<\/[^\s>]+>$/) {
			my ($element) = $el =~ /^<\/(\S+)>$/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $jk; return 0; }
			if ($stack[$#stack]->{'element'} ne $element) { confess "Error: Incompatible stack element: stack='".$stack[$#stack]->{'element'}."' element='$el'" unless $jk; return 0; }
			my $stackentry = pop @stack;
			if ($#{$stackentry->{'content'}} == -1) {
				delete $stackentry->{'content'};
			}
			$pointer = $stackentry->{'parent'};
		} elsif ($el =~ /^<[^>]+\/>$/) {
			my ($element) = $el =~ /^<([^\s>\/]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $jk; return 0; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/\/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $jk; return 0; }
				$attr{$name} = $value;
			}
			my $entry = { element => $element, attrs => \%attr, parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} elsif ($el =~ /^<[^\s>\/][^>]*>$/) {
			my ($element) = $el =~ /^<([^\s>]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $jk; return 0; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $jk; return 0; }
				$attr{$name} = $value;
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
			confess "Error: Strange element: '$el'" unless $jk; return 0;
		}
	}
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
				$xml .= " ".$attrname.'="'.$stuff->{'attrs'}{$attrname}.'"';
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
		push @{$object->{'content'}}, { value => "\n".("\t"x($tabs+1)), parent => $object };
		push @{$object->{'content'}}, $children[$i];
	}
	push @{$object->{'content'}}, { value => "\n".("\t"x($tabs)), parent => $object };
	
	for my $i (0..$#{$object->{'content'}}) {
		&_tidy_object($object->{'content'}[$i], $tabs+1);
	}
}


=head2 simple_to_xml($simple_array_ref)

Produces a raw XML string from an array reference such as this one: [ thing => [ name => 'John', location => [ city => 'New York', country => 'U.S.A.' ] ] ]

=cut

sub simple_to_xml {
	my $arref = shift;
	if ($arref eq 'XML::MyXML') { $arref = shift; }

	my $xml = '';

	while (@$arref) {
		my $key = shift @$arref;
		my ($tag) = $key =~ /^(\S+)/g;
		confess "Error: Strange key: $key" if ! defined $tag;
		my $value = shift @$arref;

		if (! ref $value) {
			$xml .= "<$key>"._encode($value)."</$tag>";
		} else {
			$xml .= "<$key>".simple_to_xml($value)."</$tag>";
		}
	}
	return $xml;
}

=head2 xml_to_simple($raw_xml)

Produces a very simple hash object from the raw XML string provided. An example hash object created thusly is this: { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } }

Since the object created is a hashref, duplicate keys will be discarded. WARNING: This function only works on very simple XML strings, i.e. children of an element may not consist of both text and elements (child elements will be discarded in that case)

=cut

sub xml_to_simple {
	my $xml = shift;
	if ($xml eq 'XML::MyXML') { $xml = shift; }

	my $object = &xml_to_object($xml);

	return &_objectarray_to_simple([$object]);
}

sub _objectarray_to_simple {
	my $object = shift;

	if (! defined $object) { return undef; }

	my $hashref = {};

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			$hashref->{ $stuff->{'element'} } = &_objectarray_to_simple($stuff->{'content'});
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			#$value =~ s/^\s*(.*?)\s*$/$1/s;
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

Returns 1 if the $raw_xml string is valid XML (valid enough to be used by this module), and 0 otherwise

=cut

sub check_xml {
	my $xml = shift;
	return 1 if &xml_to_object($xml, 'checking');
	return 0;
}



package XML::MyXML::Object;

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

Returns the element specified by the path as an XML::MyXML::Object object. When there are more than one tags with the specified name in the last step of the path, it will return all of them as an array.

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

When the tag represented by the $obj object has only text contents, returns those contents as a string

=cut

sub value {
	my $self = shift;

	return &XML::MyXML::_decode($self->{'content'}[0]{'value'});
}

=head2 $obj->attr('attrname')

Returns the value of the 'attrname' attribute of top element. Returns undef if attribute does not exist.

=cut

sub attr {
	my $self = shift;
	my $attrname = shift;

	return $self->{'attrs'}->{$attrname};
}

=head2 $obj->simplify

Returns a very simple hashref, like the one returned with &XML::MyXML::xml_to_simple. Same restrictions and warnings apply.

=cut

sub simplify {
	my $self = shift;

	return &XML::MyXML::_objectarray_to_simple([$self]);
}

=head2 $obj->to_xml

Returns the XML string of the object, just like calling &object_to_xml( $obj )

=cut

sub to_xml {
	my $self = shift;
	
	return XML::MyXML::object_to_xml($self);
}

=head2 $obj->to_tidy_xml

Returns the XML string of the object in tidy form, just like calling &tidy_xml( &object_to_xml( $obj ) )

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
