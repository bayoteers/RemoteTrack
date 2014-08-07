# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>


=head1 NAME

Bugzilla::Extension::RemoteSync::Url

=head1 DESCRIPTION

Database object for storing bug remote sync URL.

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteSync::Url;

use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint trim);

use base qw(Bugzilla::Object);

use constant DB_TABLE => 'remotesync_url';

use constant NAME_FIELD => 'value';
use constant LIST_ORDER => 'id';

use constant DB_COLUMNS => qw(
    id
    bug_id
    source_id
    value
    last_sync
    active
);

use constant UPDATE_COLUMNS => qw(
    last_sync
    active
);

use constant DATE_COLUMNS => qw(
    last_sync
);

use constant VALIDATORS => {
};

use constant VALIDATOR_DEPENDENCIES => {
};

#############
# Accessors #
#############
sub bug_id         { return $_[0]->{bug_id} }
sub source_id      { return $_[0]->{source_id} }
sub value          { return $_[0]->{value} }
sub last_sync      { return $_[0]->{last_sync} }
sub active         { return $_[0]->{active} }

sub bug {
    my $self = shift;
    if (!defined $self->{bug_obj}) {
        $self->{bug_obj} = Bugzilla::Bug->new($self->{bug_id});
    }
    return $self->{bug_obj};
}

sub source {
    my $self = shift;
    if (!defined $self->{source_obj}) {
        $self->{source_obj} = Bugzilla::Extension::RemoteSync::Source->new(
            $self->{source_id});
    }
    return $self->{source_obj};
}

############
# Mutators #
############
sub set_last_sync    { $_[0]->set('last_sync', $_[1]); }
sub set_active       { $_[0]->set('active', $_[1]); }

##############
# Validators #
##############

1;
