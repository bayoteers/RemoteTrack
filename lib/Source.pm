# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>


=head1 NAME

Bugzilla::Extension::RemoteSync::Source

=head1 DESCRIPTION

Database object for storing sync source definitions.

Source is inherited from L<Bugzilla::Object>.

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteSync::Source;

use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util qw(trick_taint trim);

use Scalar::Util qw(blessed);

use base qw(Bugzilla::Object);


use constant DB_TABLE => 'sync_source';

use constant DB_COLUMNS => qw(
    id
    name
    type
    base_url
    from_email
);

use constant UPDATE_COLUMNS => qw(
    name
    base_url
    from_email
);

use constant VALIDATORS => {
    name => \&_check_name,
    type => \&_check_type,
    from_email => \&_check_email,
};

sub TYPES {
    my $cache = Bugzilla->request_cache;
    unless (defined $cache->{remotesync_types}) {
        my @types = qw(
            Bugzilla::Extension::RemoteSync::Source::Bugzilla
        );
        Bugzilla::Hook->process('remote_sync_source_types', {types => \@types});
        $cache->{remotesync_types} = [sort @types];
    }
    return @{$cache->{remotesync_types}};
}

#############
# Accessors #
#############
sub name            { return $_[0]->{name} }
sub type            { return $_[0]->{type} }
sub base_url        { return $_[0]->{base_url} }
sub from_email      { return $_[0]->{from_email} }

############
# Mutators #
############
sub set_name        { $_[0]->set('name', $_[1]); }
sub set_type        { $_[0]->set('type', $_[1]); }
sub set_base_url    { $_[0]->set('base_url', $_[1]); }
sub set_from_email  { $_[0]->set('from_email', $_[1]); }

##############
# Validators #
##############
sub _check_name {
    my ($invocant, $value) = @_;
    my $name = trim($value);
    ThrowUserError('invalid_parameter', {
            name => 'name',
            err => 'Name must not be empty'})
        unless $name;
    if (!blessed($invocant) || lc($invocant->name) ne lc($name)) {
        ThrowUserError('invalid_parameter', {
            name => 'name',
            err => "Source with name '$name' already exists"}
        ) if defined Bugzilla::Extension::RemoteSync::Source->new(
                {name => $name}
        );
    }
    return $name;
}

sub _check_type {
    my ($invocant, $value) = @_;
    my $type = trim($value);
    ThrowUserError('invalid_parameter', {
            name => 'type',
            err => 'Name must not be empty'})
        unless $type;
    ThrowUserError('invalid_parameter', {
            name => 'type',
            err => "'$type' is not a valid sync source type"})
        unless (grep {$type eq $_} TYPES);
    return $type;
}

sub _check_email {
    my ($invocant, $value, $name) = @_;
    my $addr_spec = $Email::Address::addr_spec;
    if ($value !~ /\P{ASCII}/ && $value =~ /^$addr_spec$/) {
        trick_taint($value);
        return $value
    } else {
        ThrowUserError('invalid_parameter', {
            name => $name,
            err => "'$value' is not a valid email address"
        });
    }
}

###########
# Methods #
###########

sub new {
    my $class = shift;
    my $obj = $class->SUPER::new(@_);
    if (defined $obj) {
        bless $obj, $obj->type;
    }
    return $obj;
}

1;
