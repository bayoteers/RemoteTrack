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

sub check_existing {
    my ($class, $url, $no_error) = @_;
    my $urlobj = $class->new({
        condition => "active = 1 AND value = ?",
        values => [$url],
    });
    if (defined $urlobj && !$no_error) {
        ThrowUserError('remotetrack_bug_exists', {
            url => $url,
            bug_id => $urlobj->bug_id,
        });
    }
    return $urlobj;
}

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
    $self->set('last_sync', DateTime->now(time_zone => 'UTC'));
}

##############
# Validators #
##############

###############
# Sync methos #
###############

sub new_changes {
    my $self = shift;
    return $self->source->fetch_changes(
        $self->value, $self->last_sync
    );
}

sub sync_from_remote {
    my ($self, $nomail) = @_;
    my $active_user = Bugzilla->user;
    my $remotetrack_user = Bugzilla::User->check(
        Bugzilla->params->{remotetrack_user}
    );
    my $changes = $self->new_changes || [];
    if (@$changes) {
        Bugzilla->set_user($remotetrack_user);
        my $dbh = Bugzilla->dbh;
        my $delta_ts = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
        $dbh->bz_start_transaction;
        for my $change_set (@$changes) {
            my $text = $self->source->comment_from_changes(
                $change_set, $self->value
            );
            my $comment_tag = Bugzilla->params->{remotetrack_comment_tag};
            my $comment = Bugzilla::Comment->create({
                bug_id => $self->bug_id,
                bug_when => $delta_ts,
                thetext => $text,
            });
            if ($comment_tag) {
                $comment->add_tag($comment_tag);
                $comment->update();
            }
        }
        $self->last_sync_now();
        $self->update();
        my $bug_changes = $self->bug->update($delta_ts);
        $dbh->bz_commit_transaction;

        $self->bug->send_changes($bug_changes) unless $nomail;
        Bugzilla->set_user($active_user);
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
