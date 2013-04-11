#file:Core/FixupHandler.pm
#---------------------------------
#!/usr/bin/perl
package Core::FixupHandler;

use strict;
use warnings;

use Apache2::Access ();
use Apache2::Reload;
use Apache2::RequestUtil ();
use Apache2::Log;

use Apache2::Const -compile => qw(OK);
use Apache::SSLLookup;

use Core::VultureUtils qw(&session );

sub handler {
    my $r   = Apache::SSLLookup->new(shift);
    my $log = $r->pnotes('log');

    $log->debug("########## FixupHandler ##########");

    #Bypass ResponseHandler and use mod_proxy
    if ( $r->pnotes('url_to_mod_proxy') ) {
        $r->set_handlers( PerlResponseHandler => undef );
        return proxy_redirect( $r, $log, $r->pnotes('url_to_mod_proxy') );
    }
}

sub proxy_redirect {
    my ( $r, $log, $url ) = @_;

    my $app = $r->pnotes('app');
    my $mc_conf = $r->pnotes('mc_conf');
    my (%session_app);
    Core::VultureUtils::session( \%session_app, $app->{timeout},
        $r->pnotes('id_session_app'),
        $log, $mc_conf, $app->{update_access_time} );
    $log->debug( "Mod_proxy is working. Redirecting to " . $url );

    #Cleaning up cookies
    #Don't send VultureApp && VultureProxy cookies
    my $cookies         = $r->headers_in->{Cookie};
    my $cleaned_cookies = '';
    foreach ( split( ';', $cookies ) ) {
        if (/([^,; ]+)=([^,;]*)/) {
            if (    $1 ne $r->dir_config('VultureAppCookieName')
                and $1 ne $r->dir_config('VultureProxyCookieName') )
            {
                $cleaned_cookies .= $1 . "=" . $2 . ";";
            }
        }
    }
    if ($cleaned_cookies){
        $r->headers_in->set( "Cookie" => $cleaned_cookies );
    }
    else{
        $r->headers_in->unset( "Cookie");
    }
    $session_app{cookie} = $cleaned_cookies;
    #Not canonicalising url (i.e : not escaping chars)
    if ( not $app->{'canonicalise_url'} ) {
        $log->debug("Skipping url canonicalising");
        my $n = $r->notes();
        $n->add( "proxy-nocanon" => "1" );
    }
    $r->filename( "proxy:" . $url );
    $r->proxyreq(2);
    $r->handler('proxy-server');
    return Apache2::Const::OK;
}

1;
