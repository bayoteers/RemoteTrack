# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Copyright (C) 2014 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

package Bugzilla::Extension::RemoteSync;
use warnings;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::RemoteSync::Util;
use Bugzilla::Extension::RemoteSync::Pages;
use Bugzilla::Extension::RemoteSync::Source;
use Bugzilla::Extension::RemoteSync::Url;

use Bugzilla::Constants;
use Bugzilla::Error;

our $VERSION = '0.01';

sub install_before_final_checks {
    my ($self, $args) = @_;
    print "Checking RemoteSync Source types...\n" unless $args->{silent};
    for my $class (values %{Bugzilla::Extension::RemoteSync::Source->CLASSES}) {
        eval "require $class"
            or die("RemoteSync Source class $class not found");
        $class->isa("Bugzilla::Extension::RemoteSync::Source")
            or die("type $class does not inherit Bugzilla::Extension::RemoteSync::Source")
    }
}

sub config_add_panels {
    my ($self, $args) = @_;
    $args->{panel_modules}->{RemoteSync} = "Bugzilla::Extension::RemoteSync::Params";
}

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{schema};

    # Tables for storing the SyncSource objects
    $schema->{remotesync_source} = {
        FIELDS => [
            id => { TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1 },
            name => { TYPE => 'varchar(64)', NOTNULL => 1, },
            class => { TYPE => 'TINYTEXT', NOTNULL => 1, },
            options => { TYPE => 'MEDIUMTEXT', NOTNULL => 1, },
        ],
        INDEXES => [
            sync_source_name_unique_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
        ],
    };

    # Tables for storing the Url objects
    $schema->{remotesync_url} = {
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
                    TABLE => 'remotesync_source',
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
    my $field = Bugzilla::Field->new({ name => 'remotesync_url' });
    if (!defined $field) {
        $field = Bugzilla::Field->create({
            name        => 'remotesync_url',
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
    $columns->{"remotesync_url"} = {
        name => "bug_rs_url.value",
        title => "Remote Sync URL" };
}

sub buglist_column_joins {
    my ($self, $args) = @_;
    my $joins = $args->{column_joins};
    $joins->{"remotesync_url"} = {
        table => "remotesync_url",
        as => "bug_rs_url",
        extra => ["bug_rs_url.active = 1"],
    };
}

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $operators = $args->{'operators'};

    $operators->{'remotesync_url'}->{_default} = \&_rs_url_search_operator;
}

sub _rs_url_search_operator {
    my ($self, $args) = @_;
    my ($chart_id, $joins) = @$args{qw(chart_id joins)};
    my $table = "bug_rs_url_$chart_id";
    push(@$joins, {
        table => "remotesync_url",
        as => $table,
        extra => ["$table.active = 1"],
    });
    $args->{full_field} = "$table.value";
}

sub object_before_delete {
    my ($self, $args) = @_;
    my $obj = $args->{object};
    if ($obj->isa('Bugzilla::BugUrl')) {
        my $rsurl = Bugzilla::Extension::RemoteSync::Url->new({
            condition => "bug_id = ? AND value = ?",
            values => [$obj->bug_id, $obj->name],
            });
        if (defined $rsurl) {
            $rsurl->set_active(0);
            $rsurl->update();
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
    # If we are editing bug via browser, we need to manually set remotesync_url,
    # because it is not included in set_all in process_bug.cgi
    my $cgi = Bugzilla->cgi;
    my $dontchange = $cgi->param('dontchange') || '';
    my $url = $cgi->param('remotesync_url');
    return if ($dontchange && $url eq $dontchange);
    $bug->set_remotesync_url($url);
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my ($obj, $old_obj, $changes) = @$args{qw(object old_object changes)};

    if ($obj->isa("Bugzilla::Bug")) {
        # Update remote sync url if it has been changed
        if ($obj->remotesync_url ne $old_obj->remotesync_url) {
            if (defined $obj->{remotesync_url_obj}) {
                $obj->{remotesync_url_obj}->set_active(0);
                $obj->{remotesync_url_obj}->update();
                delete $obj->{remotesync_url_obj};
            }
            if ($obj->remotesync_url) {
                my $urlobj = Bugzilla::Extension::RemoteSync::Url->new({
                    condition => "bug_id = ? AND value = ?",
                    values => [$obj->id, $obj->remotesync_url]
                });
                if (defined $urlobj) {
                    $urlobj->set_active(1);
                    $urlobj->update();
                } else {
                    my $source = Bugzilla::Extension::RemoteSync::Source->get_for_url(
                        $obj->remotesync_url);
                    ThrowUserError("remotesync_no_source_for_url", {
                        url => $obj->remotesync_url }) unless defined $source;
                    $urlobj = Bugzilla::Extension::RemoteSync::Url->create({
                        bug_id => $obj->id, source_id => $source->id, active => 1,
                        value => $obj->remotesync_url,
                    });
                }
                $obj->{remotesync_url_obj} = $urlobj;
                delete $obj->{new_remotesync_url};
            }
            $changes->{'remotesync_url'} = [ $old_obj->remotesync_url,
                    $obj->remotesync_url ];
        }
    }
}

sub page_before_template {
    my ($self, $params) = @_;
    my ($page) = $params->{page_id} =~/^rs_(.+)$/;
    return unless defined $page;
    $page =~ s/\./_/;
    my $handler = Bugzilla::Extension::RemoteSync::Pages->can($page);
    if (defined $handler) {
        $handler->($params->{vars});
    }
}

sub webservice {
    my ($self, $args) = @_;
    $args->{dispatch}->{'RemoteSync'} =
        "Bugzilla::Extension::RemoteSync::WebService";
}

BEGIN {
*Bugzilla::Bug::remotesync_url = sub {
    my $self = shift;
    if (defined $self->{new_remotesync_url}) {
        return $self->{new_remotesync_url};
    } elsif (!exists $self->{remotesync_url_obj}) {
        $self->{remotesync_url_obj} = Bugzilla::Extension::RemoteSync::Url->new(
            {condition => "bug_id = ? AND active = 1", values => [$self->id] });
    }
    return $self->{remotesync_url_obj} ? $self->{remotesync_url_obj}->value : '';
};

*Bugzilla::Bug::set_remotesync_url = sub {
    my ($self, $url) = @_;
    $url ||= '';
    if ($url ne $self->remotesync_url) {
        $self->{new_remotesync_url} = $url;
    }
};

*Bugzilla::Bug::remotesync_url_obj = sub {
    my $self = shift;
    $self->remotesync_url;
    return $self->{remotesync_url_obj};
};

} # END BEGIN


__PACKAGE__->NAME;
