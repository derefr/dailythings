$: << File.expand_path( File.dirname( __FILE__ ) )
$: << File.expand_path( File.join( File.dirname( __FILE__ ), 'lib') )
require 'app'
run Sinatra::Application
