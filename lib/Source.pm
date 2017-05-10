# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

=head1 NAME

Bugzilla::Extension::RemoteTrack::Source

=head1 DESCRIPTION

Database object for storing tracking source definitions.

Source is inherited from L<Bugzilla::Object>.

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteTrack::Source;

use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util qw(trick_taint trim);

use JSON;
use Scalar::Util qw(blessed);

use base qw(Bugzilla::Object);


use constant DB_TABLE => 'remotetrack_source';

use constant DB_COLUMNS => qw(
    id
    name
    class
    options
);

use constant UPDATE_COLUMNS => qw(
    name
    options
);

use constant VALIDATORS => {
    name => \&_check_name,
    class => \&_check_class,
    options => \&_check_options,
};

use constant VALIDATOR_DEPENDENCIES => {
    options => ['class'],
};

sub CLASSES {
    my $cache = Bugzilla->process_cache;
    unless (defined $cache->{remotetrack_classes}) {
        my %classes = (
            'Bugzilla::BugUrl::Bugzilla' =>
                'Bugzilla::Extension::RemoteTrack::Source::Bugzilla',
        );
        Bugzilla::Hook::process('remotetrack_source_classes', {classes => \%classes});
        $cache->{remotetrack_classes} = \%classes;
    }
    return $cache->{remotetrack_classes};
}

use constant REQUIRED_METHODS => qw(
    check_options
    fetch_comments
    fetch_changes
    fetch_full
    url_to_id
    id_to_url
);

sub check_sources {
    while ( my ($url_class, $source_class) = each %{CLASSES()} ) {
        eval "require $url_class"
            or die("BugUrl class $url_class not found");
        $url_class->isa("Bugzilla::BugUrl")
            or die("$url_class is not a Bugzilla::BugUrl sub class");

        eval "require $source_class"
            or die("RemoteTrack Source class $source_class not found");
        $source_class->isa("Bugzilla::Extension::RemoteTrack::Source")
            or die("type $source_class does not inherit Bugzilla::Extension::RemoteTrack::Source");
        for my $method (REQUIRED_METHODS) {
            $source_class->can($method)
                or die("$source_class does not implement $method");
        }
    }
}

sub get_source_class {
    my $class = shift;
    $class = CLASSES->{$class};
    eval "use $class"; die $@ if $@;
    return $class;
}

#############
# Accessors #
#############
sub name         { return $_[0]->{name} }
sub class {
    my $class = $_[0]->{class};
    eval "use $class"; die $@ if $@;
    return $class;
}

sub options {
    my $self = shift;
    if (!defined $self->{options_hash}) {
        $self->{options_hash} = $self->{options} ? decode_json($self->{options}) : {};
    }
    return $self->{options_hash};
}

sub options_json {
    my $self = shift;
    return $self->{options} || "{}";
}
############
# Mutators #
############
sub set_name         { $_[0]->set('name', $_[1]); }
sub set_class        { $_[0]->set('class', $_[1]); }

sub set_options {
    my ($self, $opts) = @_;
    if (!ref($opts)) {
        $opts = decode_json($opts);
    }
    $self->set('options', $opts);
    $self->{options_hash} = decode_json($self->{options});
}

sub set_option {
    my ($self, $key, $value) = @_;
    my %opts = %{$self->options};
    $opts{$key} = $value;
    $self->set_options(\%opts);
}

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
        ) if defined Bugzilla::Extension::RemoteTrack::Source->new(
                {name => $name}
        );
    }
    return $name;
}

sub _check_class {
    my ($invocant, $value) = @_;
    my $class = trim($value);
    ThrowUserError('invalid_parameter', {
            name => 'class',
            err => 'Class must be defined'})
        unless $class;
    ThrowUserError('invalid_parameter', {
            name => 'class',
            err => "'$class' is not a valid tracking source class"})
        unless defined CLASSES->{$class};
    return $class;
}

sub _check_options {
    my ($invocant, $opts, undef, $params) = @_;
    my $class = blessed($invocant) ? $invocant : get_source_class($params->{class});
    $opts ||= {};
    if (!ref($opts)) {
        $opts = decode_json($opts);
    }
    $opts = $class->check_options($opts);
    return encode_json($opts);
}

###########
# Methods #
###########

sub new {
    my $class = shift;
    my $obj = $class->SUPER::new(@_);
    if (defined $obj) {
        my $type = CLASSES->{$obj->class};
        eval "use $type"; die $@ if $@;
        bless $obj, $type;
    }
    return $obj;
}

sub create {
    my $class = shift;
    my $obj = $class->SUPER::create(@_);
    my $type = CLASSES->{$obj->class};
    eval "use $type"; die $@ if $@;
    bless $obj, $type;
    return $obj;
}

sub get_for_url {
    my ($class, $url) = @_;
    for my $source ($class->get_all) {
        return $source if ($source->is_valid_url($url));
    }
    return;
}

sub _do_list_select {
    my $class = shift;
    my $objects = $class->SUPER::_do_list_select(@_);

    foreach my $obj (@$objects) {
        my $type = CLASSES->{$obj->class};
        eval "use $type"; die $@ if $@;
        bless $obj, $type;
    }
    return $objects
}

sub is_valid_url {
    my ($self, $url) = @_;
    my $uri = new URI($url);
    return $self->class->should_handle($uri) ? 1 : 0;
}

sub post_changes {
    my ($self, $url, $bug, $changes) = @_;
    return 0;
}

sub create_tracking_bug {
    my ($self, $url) = @_;
    my $dbh = Bugzilla->dbh;

    if(!ref($self)) {
        $self = $self->get_for_url($url);
        ThrowUserError("remotetrack_invalid_url", {url => $url})
            unless defined $self;
    }
    $url = $self->normalize_url($url);

    my $data = $self->fetch_full($url);
    ThrowUserError('remotetrack_item_not_found', {url => $url})
        unless defined $data;
    my $params = $self->get_new_bug_params($data);

    my $active_user = Bugzilla->user;
    unless ($active_user and $active_user->id) {
        Bugzilla->set_user(
            Bugzilla::User->check(Bugzilla->params->{remotetrack_user})
        );
    }

    $dbh->bz_start_transaction();
    my $bug = Bugzilla::Bug->create($params);
    my $trackurl = Bugzilla::Extension::RemoteTrack::Url->create({
        bug_id => $bug->id,
        source_id => $self->id,
        value => $url,
        last_sync => $bug->creation_ts,
        active => 1,
    });
    $bug->{remotetrack_url_obj} = $trackurl;
    if (Bugzilla->params->{remotetrack_comment_tag}) {
        $bug->comments->[0]->add_tag(
            Bugzilla->params->{remotetrack_comment_tag}
        );
        $bug->comments->[0]->update();
    }
    $dbh->bz_commit_transaction();

    $bug->send_changes();
    Bugzilla->set_user($active_user);
    return $bug;
}

sub get_new_bug_params {
    my ($self, $data) = @_;
    my $params = {
        product => Bugzilla->params->{remotetrack_default_product},
        component => Bugzilla->params->{remotetrack_default_component},
        version => Bugzilla->params->{remotetrack_default_version},
        see_also => $data->{url},
        short_desc => $data->{summary},
        comment => $self->comment_from_data($data),
        alias => $self->url_to_alias($data->{url}),
    };

    Bugzilla::Hook::process(
        'remotetrack_new_bug_params',
        {
            source => $self,
            params => $params,
            data => $data,
        }
    );
    return $params;
}

sub comment_from_data {
    my ($self, $data) = @_;
    my $comment;
    my $template = Bugzilla->template;
    $template->process(
        'remotetrack/local_comment.txt.tmpl', $data, \$comment
    ) || ThrowTemplateError($template->error());
    return $comment;
}

sub url_to_alias {
    my ($self, $url) = @_;
    if (!ref $self) {
        $self = $self->get_for_url($url);
    }
    return $self->name . "#" . $self->url_to_id($url);
}

sub alias_to_url {
    my ($self, $alias) = @_;
    my ($name, $id) = split(/#/, $alias);
    return unless ($name && $id);
    if (ref $self) {
        if ($name ne $self->name) {
            ThrowCodeError('remotetrack_invalid_alias_for_source', {
                alias => $alias,
                source => $self,
            });
        }
    } else {
        $self = $self->check($name);
    }
    return $self->id_to_url($id);
}

sub normalize_url {
    my ($self, $url) = @_;
    if (!ref $self) {
        $self = $self->get_for_url($url);
        return unless $self;
    } elsif (!$self->is_valid_url($url)) {
        return;
    }
    my $id = $self->url_to_id($url);
    return $self->id_to_url($id);
}

1;
