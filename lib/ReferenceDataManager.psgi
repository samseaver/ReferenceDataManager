use ReferenceDataManagerImpl;

use ReferenceDataManagerServer;
use Plack::Middleware::CrossOrigin;



my @dispatch;

{
    my $obj = ReferenceDataManagerImpl->new;
    push(@dispatch, 'ReferenceDataManager' => $obj);
}


my $server = ReferenceDataManagerServer->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler = Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");
