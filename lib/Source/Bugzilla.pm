# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2014-2017 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jolla.com>

=head1 NAME

Bugzilla::Extension::RemoteTrack::Source::Bugzilla

=head1 DESCRIPTION

Interface for Bugzilla Source

=cut

use strict;
use warnings;

package Bugzilla::Extension::RemoteTrack::Source::Bugzilla;

use base qw(Bugzilla::Extension::RemoteTrack::Source);

use Bugzilla::Error;
use Bugzilla::Util qw(datetime_from);

use Data::Dumper;
use Email::Address;
use XMLRPC::Lite;
use List::Util qw(any none);

sub check_options {
    my ($invocant, $options) = @_;
    for my $key (keys %$options) {
        my $value = $options->{$key};
        if ($key eq 'base_url') {
            my $uri = URI->new($value);
            ThrowUserError('invalid_parameter', {
                name => 'options->base_url',
                err => 'base_url has to be http(s)://...'}
            ) unless ($uri->scheme =~ /https?/);
            $value = $uri->scheme . ":" . $uri->opaque;
            $value .= "/" unless ($value =~ /\/$/);
        } elsif ($key eq 'from_email') {
            unless (!$value || ($value !~ /\P{ASCII}/
                && $value =~ /^${Email::Address::addr_spec}$/))
            {
                ThrowUserError('invalid_parameter', {
                    name => 'from email',
                    err => "'$value' is not a valid email address"
                });
            }
        } elsif (any {$key eq $_} qw(post_comments post_changes http_auth)) {
            $value = $value ? 1 : 0
        } elsif (none {$key eq $_} qw(username password excluded_fields) ) {
            $value = undef;
        }
        if (defined $value) {
            $options->{$key} = $value;
        } else {
            delete $options->{$key};
        }
    }
    if (!defined $options->{base_url}) {
        ThrowUserError('invalid_parameter', {
            name => 'options->base_url',
            err => 'base_url is required' });
    }
    return $options;
}

sub handle_mail_notification {
    my ($self, $email) = @_;
    my ($from) = Email::Address->parse($email->header('From'));
    return 0 unless defined $from;
    my $bz_url = $email->header('X-Bugzilla-URL') || '';
    my $action = $email->header('X-Bugzilla-Type') || '';
    return 0 if ($self->options->{base_url} ne $bz_url
                 || $self->options->{from_email} ne $from->address
                 || (none {$action eq $_} qw(changed new))
    );

    my $msgid = $email->header('Message-ID');
    my ($id) = $msgid =~ /^<bug-(\d*)-/;
    if (!$id) {
        ThrowCodeError('remotetrack_email_error', {
            err => "Failed to parse bug ID from message ID '$msgid'",
        });
    }
    my $url = $self->options->{base_url}."show_bug.cgi?id=$id";
    if ($action eq 'changed') {
        my $urls = Bugzilla::Extension::RemoteTrack::Url->match({
            source_id => $self->id,
            value => $url,
            active => 1,
        });
        for my $url (@$urls) {
            $url->sync_from_remote();
        }
    } elsif ($action eq 'new') {
        my $bug = $self->create_tracking_bug($url);
    }
    return 1;
}

sub is_valid_url {
    my ($self, $url) = @_;
    return 0 unless $self->SUPER::is_valid_url($url);
    my $base = $self->options->{base_url};
    return ($url =~ /^$base/) ? 1 : 0;
}

sub url_to_id {
    my ($self, $url) = @_;
    ThrowCodeError('invalid_parameter',
        {
            name => 'url',
            err => "URL '$url' is not a valid url for source ".$self->name,
        }
    ) unless $self->is_valid_url($url);
    my ($bug_id) = $url =~ /id=(\d+)/;
    return $bug_id;
}

sub id_to_url {
    my ($self, $id) = @_;
    return $self->options->{base_url} . "show_bug.cgi?id=$id";
}

sub fetch_changes {
    my ($self, $url, $since, $include_description) = @_;
    my $bug_id = $self->url_to_id($url);
    $since = $since ? datetime_from($since) : undef;
    my $params = {ids => [$bug_id]};
    if ($since) {
        $since = datetime_from($since);
        $params->{new_since} = $since->ymd('').'T'.$since->hms.'Z';
    }

    # Fetch comments
    my $result = $self->_xmlrpc('Bug.comments', $params);
    return unless defined $result;

    my @comments;
    my $first = 1;
    for my $c (@{$result->{bugs}->{$bug_id}->{comments}}) {
        if ($first) {
            $first = 0;
            next unless $include_description;
        }
        my $when = datetime_from($c->{creation_time});
        push(@comments,
            {
                who => $c->{creator},
                when => $when,
                comment => $c->{text},
                url => $self->_comment_url($bug_id, $c->{count})
            }
        );
    }

    # Fetch changes
    delete $params->{new_since};
    $result = $self->_xmlrpc('Bug.history', $params);
    return unless defined $result;

    my @changes;
    my @excluded = $self->_excluded_fields;
    for my $c (@{$result->{bugs}->[0]->{history}}) {
        my $when = datetime_from($c->{when});
        next if ($since && $since > $when);
        for my $f (@{$c->{changes}}) {
            next if (grep {$_ eq $f->{field_name}} @excluded);
            push(@changes,
                {
                    who => $c->{who},
                    when => $when,
                    field => $f->{field_name},
                    from => $f->{removed},
                    to => $f->{added},
                }
            );
        }
    }

    # Sort and group changes by timestamp
    my @sorted = sort { $a->{when} <=> $b->{when} } (@comments, @changes);
    my @grouped;
    my $group = { changes => [] };
    for my $c (@sorted) {
        if (defined $group->{when} && $group->{when} != $c->{when}) {
            push @grouped, $group;
            $group = { changes => [] };
        }
        $group->{when} = delete $c->{when};
        $group->{who} = delete $c->{who};
        push @{$group->{changes}}, $c;
    }
    if (@{$group->{changes}}) {
        push @grouped, $group;
    }
    return \@grouped;
}

sub fetch_full {
    my ($self, $url) = @_;
    my $bug_id = $self->url_to_id($url);
    my $params = {ids => [$bug_id]};
    my $result = $self->_xmlrpc('Bug.get', $params);
    return unless $result;
    my $raw_data = $result->{bugs}->[0];
    return unless $raw_data;

    my $changes = $self->fetch_changes($url, undef, 1);

    # Description is the first comment that is in the first change set
    my $first = shift @$changes;
    my $description = $first->{changes}->[0]->{comment};

    return {
        url => $url,
        raw_data => $raw_data,
        fields => $self->_filter_fields($raw_data),
        summary => $raw_data->{summary},
        description => $description,
        changes => $changes,
    };
}

sub _filter_fields {
    my ($self, $data) = @_;
    my @excluded = $self->_excluded_fields;
    my %fields;
    while (my ($key, $value) = each %$data) {
        next if (grep {$_ eq $key} @excluded);
        if (ref($value) eq 'ARRAY') {
            $value = join(', ', @$value);
        }
        $fields{$key} = $value;
    }
    return \%fields;
}

sub _excluded_fields {
    my $self = shift;
    return (
        qw(
            assigned_to_detail
            cc_detail
            creator_detail
            is_cc_accessible
            is_confirmed
            is_creator_accessible
            is_open
        ),
        split(/[,\s]+/, $self->options->{excluded_fields} || ''),
    );
}

sub _comment_url {
    my ($self, $bug_id, $cnum) = @_;
    return defined $cnum ?
        $self->options->{base_url}."show_bug.cgi?id=$bug_id#c$cnum" :
        '';
}

sub _can_post_comment {
    my $self = shift;
    return ($self->options->{username} && $self->options->{password}) ? 1 : 0;
}

sub _post_comment {
    my ($self, $url, $comment) = @_;
    return 0 unless $self->_can_post_comment;
    my $bug_id = $self->url_to_id($url);
    my $token = $self->_rpctoken;
    if (!$token) {
        return 0;
    }
    my $result = $self->_xmlrpc('Bug.add_comment',
        {
            id => $bug_id, comment => $comment, Bugzilla_token => $token,
        }
    );
    return $result ? 1 : 0;
}

sub post_changes {
    my ($self, $url, $bug, $changes) = @_;
    return 0 unless ($self->_can_post_comment && $self->options->{post_changes});

    my %vars;
    my @templates;
    if (defined $changes->{remotetrack_url}) {
        push(@templates, Bugzilla->params->{remotetrack_tracking_change_tmpl});
        $vars{tracking} = $changes->{remotetrack_url}->[0] eq $url ? 0 : 1;
    }
    if (defined $changes->{bug_status}) {
        push(@templates, Bugzilla->params->{remotetrack_status_change_tmpl});
        $vars{status} = $changes->{bug_status};
    }
    return 0 unless (@templates);

    my $message;
    my $message_template = join("\n", @templates);
    my $template = Bugzilla->template;
    $template->process(\$message_template, \%vars, \$message)
        || ThrowTemplateError($template->error());
    return $self->_post_comment($url, $message);
}

sub _rpctoken {
    my $self = shift;
    if (!defined $self->{_rpctoken}) {
        my $result = $self->_xmlrpc('User.login',
            {
                login => $self->options->{username},
                password => $self->options->{password},
            }
        );
        if ($result) {
            $self->{_rpctoken} = $result->{token};
        }
    }
    return $self->{_rpctoken};
}

sub _xmlrpc {
    my ($self, $method, $params) = @_;

    my $response = eval { $self->_rpcproxy->call($method, $params) };
    my $err = $@ ? $@ : $response->fault ? $response->faultstring : undef;
    if ($err) {
        local $Data::Dumper::Indent = 0;
        local $Data::Dumper::Purity = 1;
        warn "Remote Bugzilla XMLRPC call $method(".Dumper($params).") failed: ". $err;
        $self->{error} = "Remote call failed: $err";
        return;
    }
    return $response->result;
}

sub _rpcproxy {
    my $self = shift;
    if (!defined $self->{_rpcproxy}) {
        my $uri = URI->new($self->options->{base_url});
        my @path = $uri->path_segments();
        push(@path, 'xmlrpc.cgi');
        $uri->path_segments(@path);
        if ($self->options->{http_auth}) {
            my $userinfo = $self->options->{username} . ':' . $self->options->{password};
            $uri->userinfo($userinfo);
        }
        $self->{_rpcproxy} = XMLRPC::Lite->proxy($uri->as_string);
        my $proxy_url = Bugzilla->params->{'proxy_url'};
        if ($proxy_url) {
            $self->{_rpcproxy}->transport->proxy->proxy('http' => $proxy_url);
            if (!$ENV{HTTPS_PROXY}) {
                # LWP does not handle https over proxy, so by setting the env
                # variables the proxy connection is handled by underlying library
                my $pu = URI->new($proxy_url);
                $ENV{HTTPS_PROXY} = $pu->scheme.'://'.$pu->host.':'.$pu->port;
                my ($user, $pass) = split(':', $pu->userinfo || "");
                $ENV{HTTPS_PROXY_USERNAME} = $user if defined $user;
                $ENV{HTTPS_PROXY_PASSWORD} = $pass if defined $pass;
            }
        } else {
            $self->{_rpcproxy}->transport->env_proxy;
        }
    }
    return $self->{_rpcproxy};
}
1;
