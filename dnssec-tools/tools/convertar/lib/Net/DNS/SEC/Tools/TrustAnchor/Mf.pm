package Net::DNS::SEC::Tools::TrustAnchor::Mf;

use strict;
use Net::DNS::SEC::Tools::TrustAnchor;

our @ISA = qw(Net::DNS::SEC::Tools::TrustAnchor);
our $VERSION = '0.1';

use XML::Simple;

sub init_extras {
    my $self = shift;
    # XXX: allow for other contexts besides :
    $self->{'trailer'} = "; End of file\n";
    $self->{'commentprefix'} = ";";
}

sub read_content {
    my ($self, $location, $options) = @_;

    my $lastname;

    $location ||= $self->{'file'};
    $options ||= $self->{'options'};

    my $doc = { delegation => {}};

    open(I, "<", $location);
    while (<I>) {
	if (/^\s*; EIVER/) {
	    my $localinfo =
	      $self->parse_extra_info_string($_, $doc, ";");
	}

	next if (/^\s*;/);

	if (/^\s*(\S*)\s+DNSKEY\s+(\d+)\s+(\d+)\s+(\d+)\s+(.*)/) {
	    my ($name, $flags, $alg, $digesttype, $content) =
	      ($1, $2, $3, $4, $5);
	    $name ||= $lastname;
	    $lastname = $name;
	    $content =~ s/ //g;
	    push @{$doc->{'delegation'}{$name}{'dnskey'}},
	      {
	       flags => $flags,
	       algorithm => $alg,
	       digesttype => $digesttype,
	       content => $content,
	      };
	} elsif (/^\s*(\S*)\s+DS\s+\s+(\d+)\s+(\d+)\s+(\d+)\s+(.*)/) {
	    my ($name, $keytag, $alg, $digesttype, $content) =
	      ($1, $2, $3, $4, $5);
	    $name ||= $lastname;
	    $lastname = $name;
	    $content =~ s/ //g;
	    push @{$doc->{'delegation'}{$name}{'ds'}},
	      {
	       keytag => $keytag,
	       algorithm => $alg,
	       digesttype => $digesttype,
	       content => $content,
	      };
	}
    }

    return $doc;
}

sub write_header {
    my ($self, $fh, $options, $data) = @_;
    $fh->print("
;
; Trust Anchor Repository generated by convertar
; (Master file format)
;
;
; Serial: $data->{'serial'}
;
");
}


sub write_ds {
    my ($self, $fh, $name, $record) = @_;
    my $status;
    $fh->printf("\t%15s DS     %5d $record->{algorithm} $record->{digesttype} $record->{content}\n", $name, $record->{keytag});
}

sub write_dnskey {
    my ($self, $fh, $name, $record) = @_;
    my $status;
    $fh->printf("\t%15s DNSKEY $record->{flags} $record->{algorithm} $record->{digesttype} $record->{content}\n", $name);
}

=pod

=cut

