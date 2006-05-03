package XML::MyXML;

use warnings;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml);
use Carp;

=head1 NAME

XML::MyXML - The new XML::MyXML!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml);

    my $xml = '<item><name>Table</name><price>10.00</price></item>';
    print tidy_xml($xml);

=head1 EXPORT

tidy_xml, object_to_xml, xml_to_object, simple_to_xml

=head1 FUNCTIONS

=cut

sub encode {
	my $string = shift;
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

sub decode {
	my $string = shift;
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



sub xml_to_object {
	my $xml = shift;

	# Preprocess
	$xml =~ s/^(\s*<\?[^>]*\?>)*\s*//;
	#my @els = grep {$_ =~ /\S/} $xml =~ /(<[^>]*?>|[^<>]+)/g;
	my @els = $xml =~ /(<[^>]*?>|[^<>]+)/g;
	my @stack;
	my $object = { content => [] };
	#my $pointer = $object;
	my $pointer = $object;
	foreach my $el (@els) {
		if ($el =~ /^<\?[^>]*\?>$/) {
			next;
		} elsif ($el =~ /^<\/[^\s>]+>$/) {
			my ($element) = $el =~ /^<\/(\S+)>$/g;
			if (! length($element)) { confess "Error: Strange element: '$el'"; }
			if ($stack[$#stack]->{'element'} ne $element) { confess "Error: Incompatible stack element: stack='".$stack[$#stack]->{'element'}."' element='$el'"; }
			my $stackentry = pop @stack;
			if ($#{$stackentry->{'content'}} == -1) {
				delete $stackentry->{'content'};
#				my $entry = { element => undef, attrs => {}, value => '', parent => $stackentry };
#				push @{$stackentry->{'content'}}, $entry;
			}
			$pointer = $stackentry->{'parent'};
		} elsif ($el =~ /^<[^>]+\/>$/) {
			my ($element) = $el =~ /^<([^\s>\/]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'"; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/\/>$//;
			my @attrs = $el =~ /(\s+\S+)/g;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, $value) = $attr =~ /^\s*(\S+)\s*=\s*['"](.*?)['"]\s*$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'"; }
				$attr{$name} = $value;
			}
			my $entry = { element => $element, attrs => \%attr, parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			#my $entry = { element => $element, (scalar(keys %attr) ? (attrs => \%attr) : ()), content => [], parent => $pointer };
			push @{$pointer->{'content'}}, $entry;
		} elsif ($el =~ /^<[^\s>\/][^>]*>$/) {
			my ($element) = $el =~ /^<([^\s>]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'"; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/>$//;
			my @attrs = $el =~ /(\s+\S+)/g;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, $value) = $attr =~ /^\s*(\S+)\s*=\s*['"](.*?)['"]\s*$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'"; }
				$attr{$name} = $value;
			}
			my $entry = { element => $element, attrs => \%attr, content => [], parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			#my $entry = { element => $element, (scalar(keys %attr) ? (attrs => \%attr) : ()), content => [], parent => $pointer };
			push @stack, $entry;
			push @{$pointer->{'content'}}, $entry;
			$pointer = $entry;
		} elsif ($el =~ /^[^<>]*$/) {
			my $entry = { value => &decode($el), parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} else {
			confess "Error: Strange element: '$el'";
		}
	}
	$object = $object->{'content'}[0];
	$object->{'parent'} = undef;
	return $object;
}

sub objectarray_to_xml {
	my $object = shift;

	my $xml = '';
	foreach my $stuff (@$object) {
		if (! defined $stuff->{'element'} and defined $stuff->{'value'}) {
			$xml .= &encode($stuff->{'value'});
		} else {
			$xml .= "<".$stuff->{'element'};
			foreach my $attrname (keys %{$stuff->{'attrs'}}) {
				$xml .= " ".$attrname.'="'.$stuff->{'attrs'}{$attrname}.'"';
				#$xml .= " ".$attr->{'name'}.'="'.$attr->{'value'}.'"';
			}
			if (! defined $stuff->{'content'}) {
				$xml .= "/>"
			} else {
				$xml .= ">"
			}
			if (defined $stuff->{'content'}) {
				$xml .= &objectarray_to_xml($stuff->{'content'});
				$xml .= "</".$stuff->{'element'}.">";
			}
		}
	}
	return $xml;
}

sub object_to_xml {
	my $object = shift;

#	my $xml = '';
#	$xml .= '<?xml version="1.1" encoding="utf-8"?>'."\n";
	#return $xml.&object_to_xml($object);
	return &objectarray_to_xml([$object]);
}

sub tidy_object {
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
		&tidy_object($object->{'content'}[$i], $tabs+1);
	}
}


sub tidy_xml {
	my $xml = shift;

	my $object = &xml_to_object($xml);
	&tidy_object($object);
	return &object_to_xml($object);
}


sub simple_to_xml {
	my $arref = shift;

	my $xml = '';

	while (@$arref) {
		my $key = shift @$arref;
		my ($tag) = $key =~ /^(\S+)/g;
		croak "Error: Strange key: $key" if ! defined $tag;
		my $value = shift @$arref;

		if (! ref $value) {
			$xml .= "<$key>$value</$tag>";
		} else {
			$xml .= "<$key>".simple_to_xml($value)."</$tag>";
		}
	}
	return $xml;
}







package XML::MyXML::Object;

sub new {
	my $class = shift;
	my $xml = shift;

	my $obj = XML::MyXML::xml_to_object($xml);
	bless $obj, $class;
	return $obj;
}

sub as_string {
	my $self = shift;
	
	my $xml = XML::MyXML::object_to_xml($self);
	return XML::MyXML::tidy_xml($xml);
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

sub value {
	my $self = shift;

	return $self->{'content'}[0]{'value'};
}

sub simplify {
	my $self = shift;

	my $hash = {};
	my @children = $self->children;
	foreach my $child (@children) {
		my $string = $child->as_string;
		($string) = $string =~ />(.*)</sg;
		$hash->{$child->{'element'}} = $string;
	}

	return $hash;
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
