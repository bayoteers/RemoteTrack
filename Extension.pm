# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteTrack;
use warnings;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::RemoteTrack::Pages;
use Bugzilla::Extension::RemoteTrack::Source;
use Bugzilla::Extension::RemoteTrack::Url;

use Bugzilla::Constants;
use Bugzilla::Error;

use List::Util qw(any);

our $VERSION = '0.01';

sub install_before_final_checks {
    my ($self, $args) = @_;
    any { $_->isa('Bugzilla::Extension::BayotBase') } @{Bugzilla->extensions}
        or die("RemoteTrack extension requires BayotBase extension");
    print "Checking RemoteTrack Source types...\n" unless $args->{silent};
    Bugzilla::Extension::RemoteTrack::Source::check_sources();
}

sub config_add_panels {
    my ($self, $args) = @_;
    $args->{panel_modules}->{RemoteTrack} = "Bugzilla::Extension::RemoteTrack::Params";
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{schema};

    # Tables for storing the SyncSource objects
    $schema->{remotetrack_source} = {
        FIELDS => [
            id => { TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1 },
            name => { TYPE => 'varchar(64)', NOTNULL => 1, },
            class => { TYPE => 'TINYTEXT', NOTNULL => 1, },
            options => { TYPE => 'MEDIUMTEXT', NOTNULL => 1, },
        ],
        INDEXES => [
            track_source_name_unique_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
        ],
    };

    # Tables for storing the Url objects
    $schema->{remotetrack_url} = {
        FIELDS => [
            id => { TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1 },
            bug_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            source_id => {
                TYPE => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'remotetrack_source',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            value => { TYPE => 'varchar(255)', NOTNULL => 1, },
            last_sync => { TYPE => 'DATETIME', },
            active => { TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 0},
        ],
        INDEXES => [
        ],
    };
}

sub install_update_db {
    my ($self, $args) = @_;
    my $field = Bugzilla::Field->new({ name => 'remotetrack_url' });
    if (!defined $field) {
        $field = Bugzilla::Field->create({
            name        => 'remotetrack_url',
            description => 'Remote Sync URL',
            type        => FIELD_TYPE_FREETEXT,
            enter_bug   => 1,
            buglist     => 1,
            custom      => 0,
        });
    }
}

sub buglist_columns {
    my ($self, $args) = @_;
    my $columns = $args->{columns};
    $columns->{"remotetrack_url"} = {
        name => "map_remotetrack_url.value",
        title => "Remote Sync URL" };
}

sub buglist_column_joins {
    my ($self, $args) = @_;
    my $joins = $args->{column_joins};
    $joins->{"remotetrack_url"} = {
        table => "remotetrack_url",
        as => "map_remotetrack_url",
        extra => ["map_remotetrack_url.active = 1"],
    };
}

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $operators = $args->{'operators'};

    $operators->{'remotetrack_url'}->{_default} = sub {
        my ($self, $args) = @_;
        my ($chart_id, $joins) = @$args{qw(chart_id joins)};
        my $table = "map_remotetrack_url_$chart_id";
        push(@$joins, {
            table => "remotetrack_url",
            as => $table,
            extra => ["$table.active = 1"],
        });
        $args->{full_field} = "$table.value";
    };
}

sub object_before_delete {
    my ($self, $args) = @_;
    my $obj = $args->{object};
    if ($obj->isa('Bugzilla::BugUrl')) {
        my $url = Bugzilla::Extension::RemoteTrack::Source->normalize_url(
            $obj->name
        );
        return unless defined $url;
        my $rt_url = Bugzilla::Extension::RemoteTrack::Url->new({
            condition => "bug_id = ? AND value = ?",
            values => [$obj->bug_id, $obj->name],
            });
        if (defined $rt_url) {
            $rt_url->set_active(0);
            $rt_url->update();
        }
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my $bug = $args->{object};
    return unless (
        Bugzilla->usage_mode == USAGE_MODE_BROWSER &&
        $bug->isa("Bugzilla::Bug")
    );
    # If we are editing bug via browser, we need to manually set remotetrack_url,
    # because it is not included in set_all in process_bug.cgi
    my $cgi = Bugzilla->cgi;
    my $url = $cgi->param('remotetrack_url');
    return if (!defined $url);
    $bug->set_remotetrack_url($url);
}

sub bug_check_can_change_field {
    my ($self, $args) = @_;
    my ($bug, $field, $new_value) = @$args{qw(bug field new_value)};
    if ($bug->remotetrack_url && $field eq 'resolution' &&
        $new_value eq 'DUPLICATE')
    {
        ThrowUserError('remotetrack_duplicate_not_allowed');
    }
}

sub bug_start_of_update {
    my ($self, $args) = @_;
    my ($bug, $old_bug, $changes, $timestamp)
        = @$args{qw(bug old_bug changes timestamp)};

    # Update remote tracking url if it has been changed
    if ($bug->remotetrack_url ne $old_bug->remotetrack_url) {
        if (defined $bug->remotetrack_url_obj) {
            # Deactivate the old URL object
            $bug->remotetrack_url_obj->set_active(0);
            $bug->remotetrack_url_obj->update();
            delete $bug->{remotetrack_url_obj};
        }
        if ($bug->remotetrack_url) {
            # Get the object for new URL
            my $urlobj = Bugzilla::Extension::RemoteTrack::Url->new({
                condition => "bug_id = ? AND value = ?",
                values => [$bug->id, $bug->remotetrack_url]
            });
            if (defined $urlobj) {
                # Activate if there is an existing one...
                $urlobj->set_active(1);
                $urlobj->update();
            } else {
                # ...or create new one if there isn't
                my $source = Bugzilla::Extension::RemoteTrack::Source->get_for_url(
                    $bug->remotetrack_url);
                ThrowUserError("remotetrack_no_source_for_url", {
                    url => $bug->remotetrack_url }) unless defined $source;
                $urlobj = Bugzilla::Extension::RemoteTrack::Url->create({
                    bug_id => $bug->id, source_id => $source->id, active => 1,
                    value => $bug->remotetrack_url,
                    last_sync => $timestamp,
                });
            }
            $bug->{remotetrack_url_obj} = $urlobj;
            delete $bug->{new_remotetrack_url};
        }
        $changes->{'remotetrack_url'} = [ $old_bug->remotetrack_url,
                $bug->remotetrack_url ];
    }
    # Update aliases as needed
    my $old_alias = $old_bug->remotetrack_url ?
        $old_bug->remotetrack_url_obj->alias : '';
    my $new_alias = $bug->remotetrack_url ?
        $bug->remotetrack_url_obj->alias : '';
    if ($old_alias && $old_alias ne $new_alias) {
        $bug->remove_alias($old_alias);
    }
    if ($new_alias) {
        # Allways add new alias, so that user can't remove it.
        # Could probably be implemented smarter
        $bug->add_alias($new_alias);
    }
}

sub bugmail_recipients {
    my ($self, $args) = @_;
    my ($bug, $diffs) = @$args{qw(bug diffs)};
    # Posting the changes to remote items needs to be done here, because in bug
    # update hooks the transaction might still get rolled back if errors occur
    my %changes = map {
            $_->{field_name} => [$_->{old}, $_->{new}]
        } @$diffs;
    return unless (%changes);

    if (defined $changes{remotetrack_url} && $changes{remotetrack_url}->[0]) {
        # Stop tracking notice to old tracking URL
        my $urlobj = Bugzilla::Extension::RemoteTrack::Url->new({
                condition => "bug_id = ? AND value = ?",
                values => [$bug->id, $changes{remotetrack_url}->[0]]
            });
        $urlobj->post_changes(\%changes) if defined $urlobj;
    }

    if ($bug->remotetrack_url) {
        $bug->remotetrack_url_obj->post_changes(\%changes);
    }
}

sub job_map {
    my ($self, $params) = @_;
    $params->{job_map}->{remotetrack_post_changes} =
            'Bugzilla::Extension::RemoteTrack::Job::PostChanges';
}

sub page_before_template {
    my ($self, $params) = @_;
    my ($page) = $params->{page_id} =~/^rt_(.+)$/;
    return unless defined $page;
    $page =~ s/\./_/;
    my $handler = Bugzilla::Extension::RemoteTrack::Pages->can($page);
    if (defined $handler) {
        Bugzilla->login(LOGIN_REQUIRED);
        $handler->($params->{vars});
    }
}

sub webservice {
    my ($self, $args) = @_;
    $args->{dispatch}->{'RemoteTrack'} =
        "Bugzilla::Extension::RemoteTrack::WebService";
}

BEGIN {
*Bugzilla::Bug::remotetrack_url = sub {
    my $self = shift;
    if (defined $self->{new_remotetrack_url}) {
        return $self->{new_remotetrack_url};
    }
    return $self->remotetrack_url_obj ? $self->remotetrack_url_obj->value : '';
};

*Bugzilla::Bug::set_remotetrack_url = sub {
    my ($self, $url) = @_;
    $url ||= '';
    if ($url ne $self->remotetrack_url) {
        ThrowUserError("remotetrack_url_change_denied")
            unless Bugzilla->user->in_group(Bugzilla->params->{remotetrack_group});
        $self->{new_remotetrack_url} = $url;
    }
};

*Bugzilla::Bug::remotetrack_url_obj = sub {
    my $self = shift;
    if (!exists $self->{remotetrack_url_obj}) {
        $self->{remotetrack_url_obj} = Bugzilla::Extension::RemoteTrack::Url->new(
            {condition => "bug_id = ? AND active = 1", values => [$self->id] });
    }
    return $self->{remotetrack_url_obj};
};

} # END BEGIN


__PACKAGE__->NAME;
