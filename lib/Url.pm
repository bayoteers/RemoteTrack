# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

=head1 NAME

Bugzilla::Extension::RemoteTrack::Url

=head1 DESCRIPTION

Database object for storing bug remote tracking URL.

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteTrack::Url;

use Bugzilla::Error;

use DateTime;

use base qw(Bugzilla::Object);

use constant DB_TABLE => 'remotetrack_url';

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
        $self->{source_obj} = Bugzilla::Extension::RemoteTrack::Source->new(
            $self->{source_id});
    }
    return $self->{source_obj};
}

############
# Mutators #
############
sub set_last_sync    { $_[0]->set('last_sync', $_[1]); }
sub set_active {
    my ($self, $value) = @_;
    if (!$self->{active} && $value) {
        $self->last_sync_now();
    }
    $self->set('active', $value);
}

sub last_sync_now {
    my $self = shift;
    $self->set('last_sync', DateTime->now(time_zone => Bugzilla->local_timezone));
}

##############
# Validators #
##############

###############
# Sync methos #
###############

sub new_comments {
    my $self = shift;
    return $self->source->fetch_comments(
        $self->value, $self->last_sync
    );
}

sub new_changes {
    my $self = shift;
    return $self->source->fetch_changes(
        $self->value, $self->last_sync
    );
}

sub sync_from_remote {
    my $self = shift;
    my @comments = @{$self->new_comments || []};
    my @changes = @{$self->new_changes || []};
    if (@comments || @changes) {
        my $data = {
            comments => \@comments,
            changes => \@changes,
            url=> $self->value
        };
        my $comment = $self->source->comment_from_data($data);

        Bugzilla->dbh->bz_start_transaction;
        $self->bug->add_comment($comment);
        my $changes = $self->bug->update();
        $self->last_sync_now();
        $self->update();
        Bugzilla->dbh->bz_commit_transaction;

        $self->bug->send_changes($changes);
        return 1;
    }
    $self->last_sync_now();
    $self->update();
    return 0;
}

sub post_changes {
    my ($self, $changes) = @_;
    if (Bugzilla->params->{'remotetrack_use_queue'}) {
        Bugzilla->job_queue->insert('remotetrack_post_changes', {
            url => $self->value, bug_id => $self->bug_id, changes => $changes,
        });
        return;
    }
    $self->source->post_changes($self->value, $self->bug, $changes);
}

sub alias {
    my ($self) = @_;
    return $self->source->url_to_alias($self->value);
}

1;
