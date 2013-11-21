require 'rubygems'
require 'bundler'
require 'sinatra'
require 'haml'

class Remzona24App << Sinatra::Base
	configure do
		set :session, true		
	end

	get '/' do
		haml: index
	end
end