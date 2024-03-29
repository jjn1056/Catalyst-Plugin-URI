package Catalyst::Plugin::URI;

use Moo::Role;
use Scalar::Util ();
use Moo::_Utils ();
use Carp 'croak';

requires 'uri_for';

our $VERSION = '0.006';

my $uri_v1 = sub {
  my ($c, $path, @args) = @_;
 
  # already is an $action
  if(Scalar::Util::blessed($path) && $path->isa('Catalyst::Action')) {
    return $c->uri_for($path, @args);
  }
 
  # Hard error if the spec looks wrong...
  croak "$path is not a string" unless ref \$path eq 'SCALAR';
  croak "$path is not a controller.action specification" unless $path=~m/^(.*)\.(.+)$/;
 
  croak "$1 is not a controller"
    unless my $controller = $c->controller($1||'');
 
  croak "$2 is not an action for controller ${\$controller->component_name}"
    unless my $action = $controller->action_for($2);
 
  return $c->uri_for($action, @args);
};

my $uri_v2 = sub {
  my ($c, $action_proto, @args) = @_;

  # already is an $action
  if(Scalar::Util::blessed($action_proto) && $action_proto->isa('Catalyst::Action')) {
    return $c->uri_for($action_proto, @args);
  }

  # Hard error if the spec looks wrong...
  croak "$action_proto is not a string" unless ref \$action_proto eq 'SCALAR';

  my $action;
  if($action_proto =~/^\/?#/) {
    croak "$action_proto is not a named action"
      unless $action = $c->dispatcher->get_action_by_path($action_proto);
  } elsif($action_proto=~m/^(.*)\:(.+)$/) {
    croak "$1 is not a controller"
      unless my $controller = $c->controller($1||'');
    croak "$2 is not an action for controller ${\$controller->component_name}"
      unless $action = $controller->action_for($2);
  } elsif($action_proto =~/\//) {
    my $path = $action_proto=~m/^\// ? $action_proto : $c->controller->action_for($action_proto)->private_path;
    croak "$action_proto is not a full or relative private action path" unless $path;
    croak "$path is not a private path" unless $action = $c->dispatcher->get_action_by_path($path);
  } elsif($action = $c->controller->action_for($action_proto)) {
    # Noop
  } else {
    # Fallback to static
    $action = $action_proto;
  }
  croak "We can't create a URI from $action with the given arguments"
    unless my $uri = $c->uri_for($action, @args);

  return $uri;
};

my $uri_v3 = sub {
  my ($c, $action_proto, @args) = @_;

  # already is an $action
  if(Scalar::Util::blessed($action_proto) && $action_proto->isa('Catalyst::Action')) {
    die "We can't create a URI from '$action_proto' with the given arguments"
      unless my $uri = $c->uri_for($action_proto, @args);
    return $uri;
  }

  # Hard error if the spec looks wrong...
  die "$action_proto is not a string" unless ref \$action_proto eq 'SCALAR';

  my $action;
  if($action_proto =~/^\/?\*/) {
    croak "$action_proto is not a named action"
      unless $action = $c->dispatcher->get_action_by_path($action_proto);
  } elsif($action_proto=~m/^(.*)\:(.+)$/) {
    croak "$1 is not a controller"
      unless my $controller = $c->controller($1||'');
    croak "$2 is not an action for controller ${\$controller->component_name}"
      unless $action = $controller->action_for($2);
  } elsif($action_proto =~/\//) {
    my $path = $action_proto=~m/^\// ? $action_proto : $c->controller->action_for($action_proto)->private_path;
    croak "$action_proto is not a full or relative private action path" unless $path;
    croak "$path is not a private path" unless $action = $c->dispatcher->get_action_by_path($path);
  } elsif($action = $c->controller->action_for($action_proto)) {
    # Noop
  } else {
    # Fallback to static
    $action = $action_proto;
  }

  croak "We can't create a URI from $action with the given arguments"
    unless my $uri = $c->uri_for($action, @args);

  return $uri;
};


after 'setup_finalize', sub {
  my ($c) = @_;

  my $version = 3;
  if (my $config = $c->config->{'Plugin::URI'}) {
    $version = $config->{version} if exists $config->{version};
    $version = 1 if exists $config->{use_v1} and $config->{use_v1};
  }

  if($version == 1) {
    Moo::_Utils::_install_tracked($c, 'uri', $uri_v1);
  } elsif($version == 2) {
    Moo::_Utils::_install_tracked($c, 'uri', $uri_v2);
    
    # V2 does its own version of named actions
    my %action_hash = %{$c->dispatcher->_action_hash||+{}};
    foreach my $key (keys %action_hash) {
      if(my ($name) = @{$action_hash{$key}->attributes->{Name}||[]}) {
        croak "You can only name endpoint actions on a chain"
          if defined$action_hash{$key}->attributes->{CaptureArgs};
        croak "Named action '$name' is already defined"
          if $c->dispatcher->_action_hash->{"/#$name"};
        $c->dispatcher->_action_hash->{"/#$name"} = $action_hash{$key};      
      }
    }
    foreach my $method(qw/detach forward visit go/) {
      Moo::_Utils::_install_modifier($c, 'around', $method, sub { 
        my ($orig, $c, $action_proto, @args) = @_;
        my $action;
        if(defined($action_proto) && $action_proto =~/^\/?#/) {
          die "$action_proto is not a named action"
            unless $action = $c->dispatcher->get_action_by_path($action_proto);
        } else {
          $action = $action_proto;
        }
        $c->$orig($action, @args);
      });
    }
  } elsif($version == 3) {
    Moo::_Utils::_install_tracked($c, 'uri', $uri_v3);
  }
};

1;

=head1 NAME

Catalyst::Plugin::URI - Yet another sugar plugin for $c->uri_for

=head1 SYNOPSIS

Use the plugin in your application class:

    package MyApp;
    use Catalyst 'URI';

    MyApp->setup;

Then you can use it in your controllers:

    package MyApp::Controller::Example;

    use base 'Catalyst::Controller';

    sub make_a_url :Local {
      my ($self, $c) = @_;
      my $url = $c->uri("$controller.$action", \@args, \%query, \$fragment);
    }

This is just a shortcut with stronger error messages for:

    sub make_a_url :Local {
      my ($self, $c) = @_;
      my $url = $c->url_for(
        $c->controller($controller)->action_for($action),
          \@args, \%query, \$fragment);
    }

=head1 DESCRIPTION

B<NOTE> Starting with version C<0.003> I changed that way this works.  If you want
or need the old API for backcompatibility please set the following configuration
flag:

    MyApp->config('Plugin::URI' => { version => 1 });

B<NOTE> Starting with version C<0.005> we removed support for the hack that gave
partial support for named actions.  We are proposing this for L<Catalyst> core and
this version in earlier versions of this code didn't properly work anyway (didn't
support using an action name in a Chained declaration for example).  If you are using
and older Catalyst without core support for named actions and need the old behavior
you can set it like this:

    MyApp->config('Plugin::URI' => { version => 1 });

Currently if you want to create a URL to a controller's action properly the formal
syntax is rather verbose:

    my $url = $c->uri(
      $c->controller($controller)->action_for($action),
        \@args, \%query, \$fragment);


Which is verbose enough that it probably encourages people to do the wrong thing
and use a hard coded link path.  This might later bite you if you need to change
your controllers and URL hierarchy.

Also, this can lead to weird error messages that don't make if clear that your
$controller and $action are actually wrong.  This plugin is an attempt to both
make the proper formal syntax a bit more tidy and to deliver harder error messages
if you get the names wrong.

=head1 METHODS

This plugin adds the following methods to your context

=head2 uri

Example:

    $c->uri("$controller:$action", \@parts, \%query, \$fragment);

This is a sugar method which works the same as:

    my $url = $c->uri_for(
      $c->controller($controller)->action_for($action),
        \@args, \%query, \$fragment);

Just a bit shorter, and also we check to make sure the $controller and
$action actually exist (and raise a hard fail if they don't with an error
message that is I think more clear than the longer version.

You can also use a 'relative' specification for the action, which assumes
the current controller.  For example:

    $c->uri(":$action", \@parts, \%query, \$fragment);

Basically the same as:

    my $url = $c->uri_for(
      $self->action_for($action),
        \@args, \%query, \$fragment);

We also support a corrected version of what 'uri_for_action' meant to achieve:

  $c->uri("$action", @args);

Basically the same as:

    my $url = $c->uri_for($self->action_for($action), @args);

Where the $action string is the full or relative (to the current controller) private
name of the action.  Please note this does support path traversal with '..' so the
following means "create a URL to an action in the controller namespace above the
current one":

    my $url = $c->uri("../foo");  # $c->uri($self->action_for("../foo"));

Experimentally (in versions prior top C<0.005>) we support named actions so that you can specify a link with a custom
name:

    sub name_action :Local Args(0) Name(hi) {
      my ($self, $c) = @_;
      # rest of action
    }

    my $url = $c->uri("#hi");

This allows you to specify the action by its name from any controller.  We don't
allow you to use the same name twice, and we also throw an exception if you attempt
to add a name to an intermediate action in a chain of actions (you can only name
an endpoint).


Lastly For ease of use if the first argument is an action object we just pass it
down to 'uri_for'.  That way you should be able to use this method for all types
of URL creation.

=head1 OTHER SIMILAR OPTIONS

L<Catalyst> offers a second way to make URLs that use the action private
name, the 'uri_for_action' method.  However this suffers from a bug where
'path/action' and '/path/action' work the same (no support for relative
actions).  Also this doesn't give you a very good error message if the action
private path does not exist, leading to difficult debugging issues sometimes.
Lastly I just personally prefer to look up an action via $controller->action_for(...)
over the private path, which is somewhat dependent on controller namespace
information that you might change.

Prior art on CPAN doesn't seem to solve issues that I think actually exist (
for example older versions of L<Catalyst> required that you specify capture
args from args in a Chained action, there's plugins to address that but that
was fixed in core L<Catalyst> quite a while ago.)  This plugin exists merely as
sugar over the formal syntax and tries to do nothing else fancy.

=head1 AUTHOR

John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 SEE ALSO
 
L<Catalyst>

=head1 COPYRIGHT & LICENSE
 
Copyright 2023, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
 
=cut
