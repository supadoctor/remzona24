require 'rubygems'
require 'sinatra'
require 'bundler/setup'
Bundler.require

root_dir = File.dirname(__FILE__)
app_file = File.join(root_dir, 'remzona24.rb')
require app_file

run Remzona24App