# encoding: utf-8
require 'rubygems'
require 'bundler'
require 'sinatra'
require 'haml'
require 'bcrypt'
require 'data_mapper'
require 'keepass/password'
require 'warden'
require 'pony'
require 'json'
require 'sinatra/subdomain'
require 'net/http'
require 'uri'
require 'nokogiri'
require 'carrierwave'
require 'carrierwave/datamapper'
require 'yaml'
require 'unicode'
require 'mini_magick'
require 'will_paginate'
require 'will_paginate/data_mapper'

require './models.rb'

class Remzona24App < Sinatra::Base
  #register Sinatra::Subdomain
  set :environment, :production

#  configure :production do
#    set :port => 8888, :bind => '46.254.20.57'
#  end

#  configure :test do
#    #set :port => 8888, :bind => '0.0.0.0'
#    set :port => 8888, :bind => '46.254.20.57'
#  end

  configure do
    enable :logging, :method_override
    use Rack::Session::Cookie, :key => "rack.session", :expire_after => 31557600
    I18n.enforce_available_locales = false
    #set :edminds_api => 'dqrths629w35vurjaz5yrn7c'
    #set :vehicles => YAML.load_file("public/makes.yml")
  end
    @@text = YAML.load_file("public/texts.yml")
    @@terms = YAML.load_file("public/terms.yml")

#  Pony.options = {
#    :from => 'noreply@remzona24.ru',
#    :via => :smtp,
#    :charset => 'utf-8',
#    :via_options => {
#      :address => 'smtp.gmail.com',
#      :port => '587',
#      :enable_starttls_auto => true,
#      :user_name => 'sergey.rodionov@gmail.com',
#      :password => 'Neverfoget1',
#      :authentication => :login, # :plain, :login, :cram_md5, no auth by default
#      :domain => "localhost.localdomain" # the HELO domain provided by the client to the server
#    }
#  }

  Pony.options = {
    :from => 'РемЗона24.ру <noreply@remzona24.ru>',
    :charset => 'utf-8',
    :via => :sendmail
  }
  #Pony.mail(:to => 'sergey.rodionov@gmail.com', :subject => 'Запуск РемЗона24.ру', :body => 'Thin был запущен')

  use Warden::Manager do |config|
    # config.default_strategies :password, action: 'auth/unauthenticated'
    config.failure_app = self
    config.serialize_into_session{|user| user.id }
    config.serialize_from_session{|id| User.get(id) }

    config.scope_defaults :default,
      strategies: [:password],
      action: 'auth/unauthenticated'

    config.scope_defaults :express,
      strategies: [:express],
      action: 'auth/unauthenticated'
  end

  Warden::Manager.before_failure do |env,opts|
    env['REQUEST_METHOD'] = 'POST'
  end

  Warden::Strategies.add(:password) do
    def valid?
      params["email"] && params["password"]
    end

    def authenticate!
      user = User.first(:email => params["email"])
      if user.nil?
        session[:messagetodisplay]= @@text["notify"]["wronguserorpassword"]
      elsif user.authenticate(params["password"])
        user.update(:lastlogon => DateTime.now)
        success!(user)
        puts "Авторизация по паролю!"
      else
        session[:messagetodisplay]= @@text["notify"]["wronguserorpassword"]
      end
    end
  end

  Warden::Strategies.add(:express) do
    def authenticate!
      user = User.first(:email => params["email"])
      if user.nil?
        session[:messagetodisplay]= @@text["notify"]["wronguser"]
      else
        user.update(:lastlogon => DateTime.now)
        success!(user)
      end
    end
  end

  #helpers WillPaginate::Sinatra::Helpers

  helpers do
    def current_user
      # @current_user ||= User.get(session[:user_id]) if session[:user_id]
      if env['warden'].authenticated?
        @current_user = env['warden'].user
        #puts "Поиск текущего пользователя при авторизации по паролю"
        #puts "Результат >>>>", @current_user
        return @current_user
      end

      if env['warden'].authenticated?(:express)
        @current_user = env['warden'].user(:express)
        #puts "Поиск текущего пользователя при экспресс авторизации"
        #puts "Результат >>>>", @current_user
        return @current_user
      end
      #puts "Выход из хелпера поиска текущего пользователя"
      
      #@current_user = env['warden'].user if env['warden'].authenticated?
      #@current_user = env['warden'].user(:express) if env['warden'].authenticated?(:express)
    end
    
    def logged_in?
      current_user
    end
    
    def clearflashmessage
      session[:messagetodisplay] = nil
    end
    
    #def get_hint(*arg)
      # text["hints"][*arg]
      # @text["hints"]["email"]
      #"Fddfdgd"
    #end
    
    def get_settings(usr, param)
      usr.profile[param]
    end
    
    def h(text)
      Rack::Utils.escape_html(text)
    end
    
    def rur(text)
      text.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1 ") + " руб."
    end
    
    def fulllocation(usr)
      Placement.get(usr.placement_id).location + (Placement.get(usr.placement_id).area.length > 1 ? ", " + Placement.get(usr.placement_id).area : "") + (Placement.get(usr.placement_id).region.length > 1 ? ", " + Placement.get(usr.placement_id).region : "")
    end
    
    def vehicleinfo(order)
      v = order.vehicle
      (v.make && v.make.size > 0 ? v.make : "") + (v.mdl && v.mdl.size > 0 ? " " + v.mdl : "") + (v.year && v.year>0 ? ", год выпуска: " + v.year.to_s : "") + (v.VIN && v.VIN.size > 0 ? ", VIN: " + v.VIN : "")
    end
    
    def unreadmessages
      Message.count(:receiver => current_user, :sender.not => current_user, :unread => true)
    end

    def showverticalad?
      if logged_in?
        if current_user.adstatus == 1 || current_user.adstatus == 3
          true
        else
          false
        end
      else
        false
      end
    end

    def showverticalad
      if showverticalad?
        haml_tag :div, :class=>"uk-width-1-3" do
          haml_tag :div, :class=>"uk-panel uk-panel-box" do
            haml_concat "AD"
          end
        end
      end
    end

    def showhorizontalad?
      if logged_in?
        if current_user.adstatus == 2 or current_user.adstatus == 3
          true
        else
          false
        end
      else
        false
      end
    end

    def showhorizontalad
      if showhorizontalad?
        haml_tag :br
        haml_tag :div, :class=>"uk-width-1-1" do
          haml_tag :div, :class=>"uk-panel uk-panel-box uk-margin-top" do
            haml_concat "AD"
          end
        end
      end
    end

    def showmessage(msg, l)
      haml_tag :div,:class=>"uk-width-5-10 uk-push-#{l}-10" do
        haml_tag :div, :class=>"uk-panel uk-panel-box uk-margin-bottom" do
          haml_tag :article, :class=>"uk-comment" do
            haml_tag :header, :class=>"uk-comment-header" do
              haml_tag :img, :class=>"uk-comment-avatar", :src => User.get(msg.sender_id).avatar.avatar64.url
              haml_tag :div, :class=> "uk-comment-meta" do
                if User.get(msg.sender_id).type == "User"
                  haml_concat "Заказчик:"
                end
                if User.get(msg.sender_id).type == "Master"
                  haml_concat "Мастер:"
                end
                haml_tag :a, :href=>"/user/"+msg.sender_id.to_s do
                  haml_concat User.get(msg.sender_id).displayedname
                end
                haml_tag :br
                haml_concat "Дата:"
                haml_concat msg.date.strftime("%d.%m.%Y, %H:%M:%S")
              end
            end
            haml_tag :div, :class=>"uk-comment-body" do
              haml_concat msg.text
            end
          end
        end
      end
    end

    def showmessagebranch(msg, level)
      showmessage(msg, level)
      children = Message.all(:parent => msg)
      l = level+1
      children.each do |c|
        showmessagebranch(c, l)
      end
    end

  def showmyoffers(offerscollection)
    haml_tag :div, :class=>"uk-width-1-1" do
      haml_tag :table, :class=>"uk-table" do
        haml_tag :thead do
          haml_tag :tr do
            haml_tag :th, :class=>"uk-width-3-10" do
              haml_concat "Предложение"
            end
            haml_tag :th, :class=>"uk-width-3-10" do
              haml_concat "Исходная заявка"
            end
            haml_tag :th, :class=>"uk-width-2-10 uk-text-center" do
              haml_concat "Дата подачи"
            end
            haml_tag :th, :class=>"uk-width-2-10 uk-text-center" do
              haml_concat "Окончание"
            end
          end
        end
        haml_tag :tbody do
          offerscollection.each do |o|
            haml_tag :tr do
              haml_tag :td do
                haml_tag :a, :href=>"/offer/#{o.id}" do 
                  haml_concat "Предложение #{o.id}"
                end
              end
              haml_tag :td do
                haml_tag :a, :href=>"/order/#{o.order_id}" do 
                  haml_concat Order.get(o.order_id).title
                end
              end
              haml_tag :td, :class=>"uk-text-center" do
                haml_concat o.fd.strftime("%d.%m.%Y")
              end
              haml_tag :td, :class=>"uk-text-center" do
                if o.fd != o.td
                  haml_concat o.td.strftime("%d.%m.%Y")
                else
                  haml_tag :span, :class=>"uk-text-center" do
                    haml_concat "-"
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def showmyorders(orderscollection)
    haml_tag :div, :class=>"uk-width-1-1" do
      haml_tag :table, :class=>"uk-table" do
        haml_tag :thead do
          haml_tag :tr do
            haml_tag :th, :class=>"uk-width-3-10" do
              haml_concat "Заголовок"
            end
            haml_tag :th, :class=>"uk-width-3-10" do
              haml_concat "Описание"
            end
            haml_tag :th, :class=>"uk-width-1-10" do
              haml_concat "Срок окончания"
            end
            haml_tag :th, :class=>"uk-width-1-10 uk-text-center" do
              haml_tag :i, :class=>"uk-icon-eye", :title=>"Просмотры"#, data: {"uk-tooltip": ""}
            end
            haml_tag :th, :class=>"uk-width-1-10 uk-text-center" do
              haml_tag :i, :class=>"uk-icon-comments-o", :title=>"Предложения"#, data: {"uk-tooltip": ""}
            end
            haml_tag :th, :class=>"uk-width-1-10 uk-text-center" do
              haml_tag :i, :class=>"uk-icon-question-circle", :title=>"Обсуждения"#, data: {"uk-tooltip": ""}
            end
          end
        end
        haml_tag :tbody do
          orderscollection.each do |o|
            haml_tag :tr do
              haml_tag :td do
                haml_tag :a, :href=>"/order/"+o.id.to_s do
                  haml_concat o.title
                end
              end
              haml_tag :td do
                haml_tag :div, :class=>"uk-text-small" do
                  haml_concat o.subject
                end
              end
              haml_tag :td, :class=>"uk-text-center" do
                if o.fd != o.td
                  haml_concat o.td.strftime("%d.%m.%Y")
                else
                  haml_tag :span, :class=>"uk-text-center" do
                    haml_concat "-"
                  end
                end
              end
              haml_tag :td, :class=>"uk-text-center" do
                haml_concat o.views
              end
              haml_tag :td, :class=>"uk-text-center" do
                haml_concat Offer.count(:order_id => o.id)
              end
              haml_tag :td, :class=>"uk-text-center" do
                haml_concat Message.count(:order_id => o.id) #, :sender.not => current_user)
              end
            end
          end
        end
      end
    end
  end

  def showmymessages(messagescollection)
    haml_tag :div, :class=>"uk-width-1-1" do
      haml_tag :table, :class=>"uk-table" do
        haml_tag :thead do
          haml_tag :tr do
            haml_tag :th
            haml_tag :th do
              haml_concat "Тема"
            end
            haml_tag :th do
              haml_concat "Отправитель"
            end
            haml_tag :th do
              haml_concat "Дата"
            end
          end
        end
        haml_tag :tbody do
          messagescollection.each do |m|
            haml_tag :tr do
              haml_tag :td do
                if m.unread
                  haml_tag :div, :class=>"uk-badge" do
                    haml_concat "Новое"
                  end
                end
              end
              haml_tag :td do
                haml_tag :a, :href=>"/message/#{m.id}" do
                  if !m.subject
                    case m.type
                    when "Offer"
                      haml_concat "Новое предложение"
                    when "Question"
                      haml_concat "Вопрос"
                    when "Accept"
                      haml_concat "Подтверждение работ"
                    when "Refuse"
                      haml_concat "Отказ"
                    end
                  else
                    haml_concat m.subject
                  end
                end
              end
              haml_tag :td do
                if m.sender.id != 1
                  haml_tag :a, :href=>"/user/"+m.sender.id.to_s do
                    haml_concat m.sender.displayedname
                  end
                else
                  haml_concat m.sender.displayedname
                end
              end
              haml_tag :td do
                haml_concat m.date.strftime("%d.%m.%Y %H:%M")
              end
            end
          end
        end
      end
    end
  end

  def descriptiontag(desc)
    if desc
      haml_tag :meta, {:content=>desc, :name=>"description"}
    else
      haml_tag :meta, {:content=>"база данных заявок на ремонт автомобилей, автомастеров, автосервисов и СТО, бесплатно разместить объявление о ремоте авто, найти заказ подряд на ремонт авто, найти автосервисы, автомастерские, цены, ремзона24", :name=>"description"}
    end
  end

  def keywordstag(tags)
    if tags && tags.size > 0
      haml_tag :meta, {:content=>tags, :name=>"keywords"}
    else
      haml_tag :meta, {:content=>"автосервис, авторемонт, автоэлектрик, диагностика, диагностика двигателя, диагностика подвески, отремонтировать автомобиль, покраска авто, развал схождение, ремонт авто, ремонт автомобиля, ремонт двигателя, ремонт иномарки, ремонт кузова, ремонт отечественных авто, подвески, ремонт ходовой, цены, ремзона, ремзона24", :name=>"keywords"}
    end
  end

  set :spider do |enabled|
    condition do
      params.has_key?('_escaped_fragment_')
    end
  end

  end

  #*************************************************************************************************************
  #subdomain :foo do
  #  get '/' do
  #    "render page for FOO"
  #  end
  #end

  #subdomain do
  #  get '/' do
  #    "render page for #{subdomain} subdomain"
  #  end
  #end
  
  #before do
  #end

  #get '/', :spider => true  do
  get '/' do
    # url = "http://geoip.elib.ru/cgi-bin/getdata.pl"
    # resp = Net::HTTP.get_response(URI.parse(url))
    # city = Nokogiri::Slop(resp.body).GeoIP.GeoAddr.Town.content
    # url = URI::encode("http://api.vk.com/method/database.getCities?v=5&country_id=1&count=1&q="+city)
    # resp = Net::HTTP.get_response(URI.parse(url))
    # puts "*******", JSON.parse(resp.body), "*******"
    @activelink = '/'
    @orders_at_mainpage_total = (Order.all(:status => 0) & (Order.all(:conditions => ['fd = td']) | Order.all(:td.gte => DateTime.now))).count
    #puts "TOTAL ORDERS >>>", @orders_at_mainpage_total
    if params[:page].nil?
      @offset = @orders_at_mainpage_total-10 > 0 ? @orders_at_mainpage_total-10 : 0
      @current_page = 1
    else
      @offset = @orders_at_mainpage_total-params[:page].to_i*10 > 0 ? @orders_at_mainpage_total-params[:page].to_i*10 : 0
      @current_page = params[:page].to_i
    end
    
    #@orders_at_mainpage = Order.all(:status => 0, :offset => @offset, :limit => 10, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
    @orders_at_mainpage = (Order.all(:status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page

    #@orders_at_mainpage = (Order.all(:status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)
    #@new_orders_at_mainpage = @orders_at_mainpage
    #@description = "база данных заявок на ремонт автомобилей, автомастеров и СТО. бесплатно разместить объявление о ремоте авто, найти заказ подряд на ремонт авто"
    if !logged_in?
      #puts "БЕЗ АУТЕТНИФИКАЦИИ"
      if !session[:siteregionplaceholder]
        session[:siteregionplaceholder] = "Россия"
      end
      haml :navbarbeforelogin do
        if session[:showmainpage]
          haml :index, :layout => :promo
        else
          session[:showmainpage] = true
          haml :promo4users
        end
      end
    else
      #puts "ПОСЛЕ АУТЕНТИФИКАЦИИ"
      haml :navbarafterlogin do
        haml :index
      end
    end
  end

  post '/' do
    session[:siteregion] = params[:siteregion]
    session[:sitearea] = params[:sitearea]
    session[:sitelocation] = params[:sitelocation]
    session[:siteregionplaceholder] = params[:sitelocation] + (params[:sitearea].size > 0 ? ", " + params[:sitearea] : "") + (params[:siteregion].size > 0 ? ", " + params[:siteregion] : "")
    if session[:sitelocation] && session[:sitelocation].size > 0
      redirect '/location/'+session[:sitelocation]
    elsif session[:sitearea] && session[:sitearea].size > 0
      redirect '/area/'+session[:sitearea]
    elsif session[:siteregion] && session[:siteregion].size > 0
      redirect '/region'+session[:siteregion]
    else
      redirect '/'
    end
  end

['/masters','/masters/*'].each do |path|
  get path do
    if params[:splat]
      if params[:splat][0].size > 0
        @showmastersinlocation = params[:splat][0]
      end
    end
    if !@showmastersinlocation
      @masters_at_mainpage = User.all(:status => 0, :type => "Master", :order => [ :lastlogon.desc ]).paginate(:page => params[:page], :per_page => 10)
    elsif
      @masters_at_mainpage = User.all(:status => 0, :type => "Master", :placement => {:location => @showmastersinlocation}, :order => [:lastlogon.desc]).paginate(:page => params[:page], :per_page => 10)
    end
    if @users_at_mainpage
      @masters_at_mainpage_total = @users_at_mainpage.count
    else
      @masters_at_mainpage_total = 0
    end
    if params[:page].nil?
      @current_page = 1
    else
      @current_page = params[:page].to_i
    end
    @total_pages = (@masters_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page

    @uniqlocations = Placement.all(:fields => [:id, :location], :unique => true, :order => [:location.asc])
    @mastersbylocation = {}
    @uniqlocations.each do |l|
      count = User.all(:status => 0, :type => "Master", :placement_id => l.id).count
      if count > 0 
        @mastersbylocation.merge!(l.location => count)
      end
    end

    @description = "база мастеров по ремонту автомобилей, найти мастера"
    @tags = "автомастер, СТО, найти матера по ремонту авто, отзыв о мастере"
    if !logged_in?
      #puts "БЕЗ АУТЕТНИФИКАЦИИ"
      haml :navbarbeforelogin do
        haml :masters
      end
    else
      #puts "ПОСЛЕ АУТЕНТИФИКАЦИИ"
      haml :navbarafterlogin do
        haml :masters
      end
    end
  end
end

  get '/region/:region' do
    @activelink = '/region'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    #@orders_at_mainpage = Order.all(:placement => {:region => params[:region]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
    @orders_at_mainpage = Order.all(:placement => {:region => params[:region]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ])).paginate(:page => params[:page], :per_page => 10)
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin do
        haml :index, :layout => :promo
      end
    else
      haml :navbarafterlogin do
        haml :index
      end
    end
  end

  get '/area/:area' do
    @activelink = '/area'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    #@orders_at_mainpage = Order.all(:placement => {:area => params[:area]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
    @orders_at_mainpage = Order.all(:placement => {:area => params[:area]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ])).paginate(:page => params[:page], :per_page => 10)
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin do
        haml :index, :layout => :promo
      end
    else
      haml :navbarafterlogin do
        haml :index
      end
    end
  end

  get '/location/:location' do
    @activelink = '/location'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:placement => {:location => params[:location]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
    @orders_at_mainpage_total = @orders_at_mainpage.count
    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    end
    @pagination = @start_page..@end_page
    if !logged_in?
      haml :navbarbeforelogin do
        haml :index, :layout => :promo
      end
    else
      haml :navbarafterlogin do
        haml :index
      end
    end
  end

  post '/reguser' do
    if params[:password] != params[:pass]
      session[:messagetodisplay] = @@text["notify"]["errorinpassword"]
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
    user = User.new(
      :email => params[:email],
      :type => "User",
      :fullname => params[:fullname],
      :created_at => DateTime.now,
      :password => params[:password],
      :placement => placement,
      :status => 0,
      :adstatus => 0,
      :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
    begin
      user.save
    rescue
      session[:messagetodisplay] = user.errors.values.join("; ")
      redirect back
    end
    session[:user_id] = user.id
    @msg = "Здравствуйте, " + user.displayedname + "!\n" + @@text["email"]["registration"] + @@text["email"]["regards"]
    Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
    env['warden'].authenticate!
    redirect '/profile'
  end

  post '/regmaster' do
    if params[:password] != params[:pass]
      session[:messagetodisplay] = @@text["notify"]["errorinpassword"]
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
    user = User.new(
      :email => params[:email],
      :type => "Master",
      :familyname => Unicode::capitalize(params[:familyname]),
      :name => Unicode::capitalize(params[:name]),
      :fathersname => Unicode::capitalize(params[:fathersname]),
      :created_at => DateTime.now,
      :password => params[:password],
      :placement => placement,
      :status => 0,
      :adstatus => 0,
      :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
    begin
      user.save
    rescue
      session[:messagetodisplay] = user.errors.values.join("; ")
      redirect back
    end
    session[:user_id] = user.id
    @msg = "Здравствуйте, " + user.displayedname + "!\n" + @@text["email"]["registration"] + @@text["email"]["regards"]
    Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
    env['warden'].authenticate!
    redirect '/profile'
  end

  get '/profile' do
    if logged_in?
      @messages = Message.all(:receiver => current_user, :sender.not => current_user, :archived => false, :order => [ :date.desc ])
      @archivedmessages = Message.all(:receiver => current_user, :sender.not => current_user, :archived => true, :order => [ :date.desc ])      
      #@newmessages = Message.count(:receiver => current_user, :sender.not => current_user, :unread => true)
      haml :navbarafterlogin do
        case @current_user.type
          when "User"
            @myactiveorders = (Order.all(:status => 0, :order => [ :fd.desc ]) | Order.all(:status => 3, :order => [ :fd.desc ])) & Order.all(:user => current_user, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
            @myclosedorders = Order.all(:user => current_user, :status => 1, :order => [ :fd.desc ]) | Order.all(:status => 0, :td.lt => DateTime.now, :conditions => ['fd <> td'], :order => [ :fd.desc ])
            @newoffers = repository(:default).adapter.select('SELECT COUNT(*) FROM offers WHERE order_id IN (SELECT id FROM orders WHERE user_id = ?) AND unread = true;', current_user.id)
            haml :userprofile
          when "Master"
            @tags = []
            @current_user.tags.all.each do |t|
              @tags << t.tag
            end
            @tags = @tags.join(", ")
            @myactiveoffers = Offer.all(:user => current_user, :order => [ :fd.desc ]) & (Offer.all(:status => 0, :order => [ :fd.desc ]) | Offer.all(:status => 2, :order => [ :fd.desc ]) | Offer.all(:status => 3, :order => [ :fd.desc ])) & (Offer.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Offer.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
            @myclosedoffers = Offer.all(:user => current_user, :order => [ :fd.desc ]) & (Offer.all(:status => 1, :order => [ :fd.desc ]) | Offer.all(:status => 4, :order => [ :fd.desc ]) | Offer.all(:conditions => ['fd <> td'], :td.lt => DateTime.now, :order => [ :fd.desc ]))
            #@mypossibilities = Order.all(:status => 0, :placement => current_user.placement, :order => [ :fd.desc ], :limit => 10)
            @mypossibilities = repository(:default).adapter.select('select * from orders where id in (select order_id from ordertaggings where tag_id in (select id from tags where tag in (select tag from tags where id in (select tag_id from usertaggings where user_id = ?)))) and status = 0 and placement_id = ? order by fd desc limit 10;', current_user.id, current_user.placement_id)
            haml :masterprofile
          when "Admin"
            haml :admin
        end
      end
    else
      redirect '/'
    end
  end

  get '/user/:id' do
    if params[:id].to_i > 1
      begin
        @user = User.get(params[:id].to_i)
      rescue
        session[:messagetodisplay] = @@text["notify"]["nouser"]
        redirect back
      ensure
        if @user.nil?
          session[:messagetodisplay] = @@text["notify"]["nouser"]
          redirect back
        end
      end
      if logged_in?
        haml :navbarafterlogin do
          @reviews = Review.all(:user => @user, :limit => 10, :order => [:date.desc])
          case @user.type
            when "User"
              haml :userview
            when "Master"
              @tags = []
              @user.tags.all.each do |t|
                @tags << t.tag
              end
              @tags = @tags.join(",")
              haml :masterview
          end
        end
      else
        session[:messagetodisplay] = @@text["notify"]["plsloginforseeuser"]
        redirect back
      end
    else
      redirect back
    end
  end
  
  get '/user/:id/reviews' do
    if params[:id].to_i > 1
      begin
        @user = User.get(params[:id].to_i)
      rescue
        session[:messagetodisplay] = @@text["notify"]["nouser"]
        redirect back
      ensure
        if @user.nil?
          session[:messagetodisplay] = @@text["notify"]["nouser"]
          redirect back
        end
      end
      if logged_in?
        haml :navbarafterlogin do
          @reviews = Review.all(:user => @user)
          haml :reviews
        end
      else
        session[:messagetodisplay] = @@text["notify"]["plsloginforuserreviews"]
        redirect back
      end
    else
      redirect back
    end
  end

  post '/updateprofile' do
    current_user
    session[:activetab] = "profile"
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
      case @current_user.type
      when "Master"
        begin
          @current_user.update(:name => params[:name], :fathersname => params[:fathersname], :familyname => params[:familyname], :description => h(params[:description]), :phone => params[:phone], :email => params[:email], :placement => placement)
          if params[:avatar] && !params[:delete_avatar]
            @current_user.update(:avatar => params[:avatar])
          end
          if params[:pricelist] && !params[:delete_pricelist]
            @current_user.update(:pricelist => params[:pricelist])
          end
          if params[:delete_avatar]
            @current_user.update(:avatar => nil)
          end
          if params[:delete_pricelist]
            @current_user.update(:pricelist => nil)
          end
          oldtags = @current_user.usertaggings
          oldtags.each {|ot| ot.destroy }
          tagsstring = params[:tags]
          tagsstring.split(",").each do |t|
            tag = @current_user.tags.first_or_create(:tag => t)
          end
        rescue
          session[:messagetodisplay] = @current_user.errors.values.join("; ")
          redirect back
        end
      when "User"
        begin
          @current_user.update(:fullname => params[:fullname], :email => params[:email], :phone => params[:phone], :placement => placement)
          if params[:avatar] && !params[:delete_avatar]
            @current_user.update(:avatar => params[:avatar])
          end
          if params[:pricelist] && !params[:delete_pricelist]
            @current_user.update(:pricelist => params[:pricelist])
          end
          if params[:delete_avatar]
            @current_user.update(:avatar => nil)
          end
          if params[:delete_pricelist]
            @current_user.update(:pricelist => nil)
          end

        rescue
          session[:messagetodisplay] = @current_user.errors.values.join("; ")
          redirect back
        end
      end
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
    session[:messagetodisplay] = @@text["notify"]["updateprofile"]
    redirect back
  end

  post '/changepassword' do
    if logged_in?
      if @current_user.password != params[:oldpass]
        session[:messagetodisplay] = "Неправильно указан старый пароль. Пожалуйста, попробуйте сменить пароль еще раз"
        redirect back
      end
      @current_user.update(:password => params[:newpass1])
      haml :navbarafterlogin do
        session[:messagetodisplay] = @@text["notify"]["updatepassword"]
        redirect back
      end
    else
      redirect back
    end
  end
  
  post '/resetpass' do
    user = User.first(:email=>params[:email])
    if !user
      session[:messagetodisplay] = @@text["notify"]["wrongemail"]
      redirect back
    else
      resetrequest = ResetPasswords.first_or_new({:email => user.email}, {:td => DateTime.now+1, :myhash => (user.email + DateTime.now.to_s)})
      begin
        resetrequest.save
      rescue
        session[:messagetodisplay] = @@text["notify"]["resetpassworderror"]
        session[:messagetodisplay] += resetrequest.errors.values.join("; ")
        redirect back
      end
      session[:messagetodisplay] = @@text["notify"]["resetpassword"]
      @msg = @@text["email"]["resetpassword1"] + request.host + ":" + request.port.to_s + "/resetpass?reset=" + resetrequest.myhash + @@text["email"]["resetpassword2"] + @@text["email"]["regards"]
      Pony.mail(:to => user.email, :subject => 'Сброс пароля на РемЗона24.ру', :body => @msg)
      redirect back
    end
  end

  get '/resetpass' do
    resetrequest = ResetPasswords.first(:myhash => params[:reset])
    if !resetrequest 
      session[:messagetodisplay] = @@text["notify"]["resetpasswordwrongemail"]
      redirect back
    elsif resetrequest.td < DateTime.now
      resetrequest.destroy
      session[:messagetodisplay] = @@text["notify"]["resetpasswordoverdue"]
      redirect back
    end
    if !logged_in?
      haml :navbarbeforelogin do
        #resetrequest.update(:myhash => DateTime.now.to_s)
        @mynewhash = resetrequest.myhash
        haml :resetpass
      end
    else
      haml :navbarafterlogin do
        haml :index
      end
    end
  end
  
  post '/updatepassword' do
    resetrequest = ResetPasswords.first(:myhash => params[:reset])
    if !resetrequest
      session[:messagetodisplay] = @@text["notify"]["resetpassworderror"]
      redirect back
    else
      if params[:newpass1] != params[:newpass2]
        session[:messagetodisplay] = @@text["notify"]["errorinpassword"]
      else
        user = User.first(:email => resetrequest.email)
        user.update(:password => params[:newpass1])
        resetrequest.update(:myhash => DateTime.now.to_s)
        session[:messagetodisplay] = @@text["notify"]["updatepassword"]
      end
      resetrequest.destroy
      redirect '/'
    end
  end
  
  post '/setmap' do
    current_user
    @current_user.update(:mapx => params[:mapx].to_f, :mapy => params[:mapy].to_f)
    redirect back
  end

  post '/updatesettings' do
    current_user
    session[:activetab] = "settings"
    settings_list = ["showemail", "showphone", "sendmessagestoemail"]
    settings_list.each do |s|
      if params.has_key?(s) && params[s.to_sym] == "on"
        @current_user.profile.update(s.to_sym => true)
      end
      if !params.has_key?(s)
        @current_user.profile.update(s.to_sym => false)
      end
    end
    session[:messagetodisplay] = @@text["notify"]["updatesettings"]
    redirect back
  end

  get '/neworder' do
    if !logged_in?
      redirect '/'
    else
      haml :navbarafterlogin do
        haml :neworder
      end
    end
  end

  post '/order' do
    fd = DateTime.now
    td = fd+params[:lifetime].to_i

    if params[:budgettype] == "1"
      budget = -1
    else
      budget = params[:budget].to_i
    end
    #puts "*******",  params[:vehiclemake], params[:vehiclemodel], params[:vehicleyear].to_i, params[:vehicleVIN]
    order = Order.new(
      :user => current_user,
      :title => h(params[:title]),
      :subject => h(params[:subject]),
      :budget => budget,
      :fd => fd,
      :td => td,
      :status => 0,
      :views => 0,
      :placement => @current_user.placement,
      :vehicle => Vehicle.new(:make => params[:vehiclemake], :mdl => h(params[:vehiclemodel]), :year => params[:vehicleyear].to_i, :VIN => h(params[:vehicleVIN])))
    begin
      order.save
    rescue
      session[:messagetodisplay] = order.errors.values.join("; ")
      redirect back
    end
    tagsstring = params[:tags]
    tagsstring.split(",").each do |t|
      tag = order.tags.first_or_create(:tag => t)
    end
    #puts "Кол-во фоток: ", params[:photos].size
    if  params[:photos] && !params[:photos].empty?
      params[:photos].each do |image|
        begin
          oi = Orderimage.create(:order => order, :image => image)
        rescue
          session[:messagetodisplay] = oi.errors.values.join("; ")
          redirect backsession[:messagetodisplay] = oi.errors.values.join("; ")
        end
        #puts oi.class
      end
    end
    session[:messagetodisplay] = @@text["notify"]["neworder"]
    redirect '/'
  end
  
  post '/expressorder' do
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
    password = KeePass::Password.generate('d{6}')
    user = User.new(
      :email => params[:email],
      :type => "User",
      :fullname => params[:fullname],
      :created_at => DateTime.now,
      :password => password,
      :placement => placement,
      :status => 0,
      :adstatus => 0,
      :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
    begin
      user.save
    rescue
      session[:messagetodisplay] = user.errors.values.join("; ")
      redirect back
    end
    session[:user_id] = user.id
    @msg = "Здравствуйте, " + user.displayedname + "!\n" + @@text["email"]["expressregistration1"] + "логин: " + user.email + "\nпароль: " + password + @@text["email"]["expressregistration2"] + @@text["email"]["regards"]
    Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)

    env['warden'].authenticate! :scope => :express

    fd = DateTime.now
    #puts "*************", params[:vehiclemake], h(params[:vehiclemodel])
    order = Order.new(
      :user => user,
      :title => h(params[:title]),
      :subject => h(params[:subject]),
      :budget => -1,
      :fd => fd,
      :td => fd,
      :status => 0,
      :views => 0,
      :placement => user.placement,
      :vehicle => Vehicle.new(:make => params[:vehiclemake], :mdl => h(params[:vehiclemodel]), :year => nil, :VIN => nil))
    begin
      order.save
    rescue
      session[:messagetodisplay] = order.errors.values.join("; ")
      redirect back
    end
    if params[:photos] && !params[:photos].empty?
      params[:photos].each do |image|
        #puts "image >>>", image
        begin
          oi = Orderimage.create(:order => order, :image => image)
        rescue
          session[:messagetodisplay] = oi.errors.values.join("; ")
          redirect backsession[:messagetodisplay] = oi.errors.values.join("; ")
        end
        #puts "oi.class >>>", oi.class
      end
    end
    session[:messagetodisplay] = @@text["notify"]["expressregistration"]
    redirect '/profile'
  end

  post '/order/:order/addoffer' do
    current_user
    order = Order.get(params[:order])
    budget = params[:budget]
    nodetails = 0
    fd = DateTime.now
    td = fd+params[:lifetime].to_i
    if params[:nodetails] == "on"
      budget = -1
      nodetails = 1
      td = fd
    end
    offer = Offer.new(
      :user => current_user,
      :order => order,
      :subject => h(params[:subject]),
      :budget => budget,
      :time => params[:time],
      :fd => fd,
      :td => td,
      :nodetails => nodetails,
      :status => 0,
      :unread => true)
    begin
      offer.save
    rescue
      session[:messagetodisplay] = offer.errors.values.join("; ")
      redirect back
    end
    int_msg = "Здравствуйте! <br/> По вашей заявке (<a href='http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + "'>" + order.title + "</a>) было размещено новое предложение. Ознакомиться с ним вы можете по этой <a href='http://" + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "'>ссылке</a>.</br>--<br/>С уважением, РемЗона24.ру"
    message = Message.new(
      :sender => User.get(1),
      :receiver => order.user,
      :type => "Offer",
      :date => DateTime.now,
      :text => int_msg,
      #:order => order,
      :unread => true,
      :type => "Offer")
    begin
      message.save
    rescue
      session[:messagetodisplay] += message.errors.values.join("; ")
      redirect back
    end
    #email_msg = "Здравствуйте!\nПо вашей заявке (http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + ") было размещено новое предложение. Ознакомиться с ним вы можете по этой ссылке: http://" + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "\n--\nС уважением, РемЗона24.ру"
    email_msg = @@text["email"]["newoffer"] + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "\n\nССылка на исходную заявку: http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + @@text["email"]["regards"]
    if get_settings(order.user, "sendmessagestoemail")
      Pony.mail(:to => order.user.email, :subject => 'Вы получили новое предложение на РемЗона24.ру', :body => email_msg)
    end
    session[:messagetodisplay] = @@text["notify"]["newoffer"]
    redirect back
  end

  post '/order/:order/reviewcontractor' do
    order = Order.get(params[:order])
    if !order.contract
      session[:messagetodisplay] = @@text["notify"]["nocontract"]
      redirect back
    end
    review = Review.new(
      :user => order.contract.contractor,
      :author => order.contract.customer,
      :text => h(params[:text]),
      :rating => params[:rating],
      :date => DateTime.now,
      :contract => order.contract)
    begin
      review.save
    rescue
      session[:messagetodisplay] = review.errors.values.join("; ")
      redirect back
    end
    session[:messagetodisplay] = @@text["notify"]["reviewcontractor"]
    redirect back
  end
  
  post '/order/:order/reviewcustomer' do
    order = Order.get(params[:order])
    if !order.contract
      session[:messagetodisplay] = @@text["notify"]["nocontract"]
      redirect back
    end
    review = Review.new(
      :user => order.contract.customer,
      :author => order.contract.contractor,
      :text => h(params[:text]),
      :rating => params[:rating],
      :date => DateTime.now,
      :contract => order.contract)
    begin
      review.save
    rescue
      session[:messagetodisplay] = review.errors.values.join("; ")
      redirect back
    end
    session[:messagetodisplay] = @@text["notify"]["reviewcustomer"]
    redirect back
  end

  post '/addquestionto' do
    #current_user
    if params.has_key?("order")
      @order = Order.get(params[:order].to_i)
      if current_user.type == "Master"
        @message = Message.new(
          :sender => current_user,
          :receiver => @order.user,
          :order => @order,
          :unread => true,
          :text => h(params[:question]),
          :date => DateTime.now,
          :type => "Question"
        )
      #  else
      #    @offer = Offer.first(:order => params[:order].to_i)
      #    @message = Message.new(
      #      :sender => current_user,
      #      :receiver => @offer.user,
      #      :order => @order,
      #      :unread => true,
      #      :text => h(params[:question]),
      #      :date => DateTime.now,
      #      :type => "Question"
      #    )
      end
      begin
        @message.save
        session[:messagetodisplay] = @@text["notify"]["messagesent"]
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
      ensure
        redirect back
      end
    end
    if params.has_key?("offer")
      @offer = Offer.get(params[:offer].to_i)
      if current_user.type == "User"
        @message = Message.new(
          :sender => current_user,
          :receiver => @offer.user,
          :offer => @offer,
          :unread => true,
          :text => h(params[:question]),
          :date => DateTime.now,
          :type => "Question"
        )
      else
        @order = Order.get(Offer.get(params[:offer].to_i).order_id)
        @message = Message.new(
          :sender => current_user,
          :receiver => @order.user,
          :offer => @offer,
          :unread => true,
          :text => h(params[:question]),
          :date => DateTime.now,
          :type => "Question"
        )
      end
      begin
        @message.save
        session[:messagetodisplay] = @@text["notify"]["messagesent"]
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["unreadnotification"] + @@text["email"]["regards"]
      if get_settings(@order.user, "sendmessagestoemail")
        Pony.mail(:to => @order.user.email, :subject => 'Непрочитанное уведомление на РемЗона24.ру', :body => email_msg)
      end
      redirect back
    end
    if params.has_key?("user")
      @message = Message.new(
        :sender => current_user,
        :receiver => User.get(params[:user]),
        :unread => true,
        :subject => h(params[:subject]),
        :text => h(params[:question]),
        :date => DateTime.now,
        :type => "Question"
      )
      begin
        @message.save
        session[:messagetodisplay] = @@text["notify"]["messagesent"]
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["unreadnotification"] + @@text["email"]["regards"]
      if get_settings(User.get(params[:user]), "sendmessagestoemail")
        Pony.mail(:to => User.get(params[:user]).email, :subject => 'Непрочитанное уведомление на РемЗона24.ру', :body => email_msg)
      end
      redirect back
    end
  end

  post '/replyto' do
    if params.has_key?("message")
      @msg = Message.get(params[:message].to_i)
      @message = Message.new(
        :sender => current_user,
        :receiver => @msg.sender,
        :unread => true,
        :subject => h(params[:subject]),
        :text => h(params[:question]),
        :date => DateTime.now,
        :order_id => @msg.order_id,
        :offer_id => @msg.offer_id,
        :type => "Question",
        :parent => @msg
      )
      begin
        @message.save
        session[:messagetodisplay] = @@text["notify"]["messagesent"]
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      @msg.update(:child => @message)
      email_msg = @@text["email"]["unreadnotification"] + @@text["email"]["regards"]
      if get_settings(@msg.sender, "sendmessagestoemail")
        Pony.mail(:to => @msg.sender.email, :subject => 'Непрочитанное уведомление на РемЗона24.ру', :body => email_msg)
      end
      redirect back
    end
  end


  get '/order/:order' do
    begin
      @order = Order.get(params[:order].to_i)
    rescue
      session[:messagetodisplay] = @@text["notify"]["noorder"]
      redirect back
    ensure
      if @order.nil? || @order.status == 2
        session[:messagetodisplay] = @@text["notify"]["noorder"]
        redirect back
      end
    end
    #@tags = []
    #@order.tags.all.each do |t|
    #  @tags << t.tag
    #end
    #@tags = @tags.join(', ')
    if logged_in? && current_user != @order.user
      views = @order.views + 1
      @order.update(:views => views)
    end
    if @order.fd != @order.td && @order.td < DateTime.now && @order.status == 0
      @order.update(:status => 1)
    end
    @photos = Orderimage.all(:order_id => params[:order].to_i)

    @offers = Offer.all(:order_id => params[:order].to_i, :order => [ :fd.desc ])
    @offers.each do |o|
      if o.fd != o.td && o.td < DateTime.now
        o.update(:status => 1)
      end
    end

    #@questionsnumber = Message.count(:order_id => params[:order].to_i, :type => "Question")
    @questionsnumber = Message.count(:order_id => params[:order].to_i)
    @alreadyreviewed = Review.first(:contract => @order.contract)

    @description = @order.title + " " + @order.subject + " " + fulllocation(@order.user)
    @tags = @order.tags.all.map(&:tag).join(', ')

    if !logged_in?
      haml :navbarbeforelogin do
        haml :orderdetails
      end
    else
      haml :navbarafterlogin do
        haml :orderdetails
      end
    end
  end
  
  get '/order/:order/comments' do
    begin
      @order = Order.get(params[:order].to_i)
    rescue
      session[:messagetodisplay] = @@text["notify"]["noorder"]
      redirect back
    ensure
      if @order.nil?
        session[:messagetodisplay] = @@text["notify"]["noorder"]
        redirect back
      end
    end

    @description = @order.title + " " + @order.subject + " " + fulllocation(@order.user)
    @tags = @order.tags.all.map(&:tag).join(', ')

    if !logged_in?
      haml :navbarbeforelogin do
        session[:messagetodisplay] = @@text["notify"]["plsloginforordercomments"]
        redirect back
      end
    else
      #@offer = Offer.get(@order.offer_id)
      #@questions = Message.all(:order_id => params[:order].to_i, :type => "Question")
      @rootquestions = Message.all(:order_id => params[:order].to_i, :parent => nil)
      haml :navbarafterlogin do
        haml :ordercomments
      end
    end
  end
  
  put '/order/:order' do
    if !logged_in?
      haml :navbarbeforelogin do
        redirect '/'
      end
    else
      haml :navbarafterlogin do
        order = Order.get(params[:order])
        if order.user != current_user
          session[:messagetodisplay] = "Вы не можете закрыть заявку"
          redirect back
        else
          order.update(:status => 1, :td => DateTime.now)
          session[:messagetodisplay] = @@text["notify"]["orderwasarchived"]
          redirect '/profile'
        end
      end
    end
  end

  delete '/order/:order' do
    if !logged_in?
      haml :navbarbeforelogin do
        redirect '/'
      end
    else
      haml :navbarafterlogin do
        order = Order.get(params[:order].to_i)
        if order.user != current_user
          session[:messagetodisplay] = @@text["notify"]["cantdeleteorder"]
          redirect back
        else
          order.update(:status => 2, :td => DateTime.now)
          session[:messagetodisplay] = @@text["notify"]["orderwasdeleted"]
          redirect '/profile'
        end
      end
    end
  end

  get '/offer/:id' do
    begin
      @offer = Offer.get(params[:id].to_i)
      if @offer.fd != @offer.td && @offer.td < DateTime.now && @offer.status == 0
        @offer.update(:status => 1)
      end
      @offer.update(:unread => false)
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect back
      end  
    end
    @order = Order.get(@offer.order_id)

    @description = @offer.subject + " " + fulllocation(@offer.user)
    @tags = @order.tags.all.map(&:tag).join(', ')

    if !logged_in?
      session[:messagetodisplay] = @@text["notify"]["plsloginforoffer"]
      redirect back
    else
      haml :navbarafterlogin do
        #@questionsnumber = Message.count(:offer_id => params[:id].to_i, :type => "Question")
        @questionsnumber = Message.count(:offer_id => params[:id].to_i)
        haml :offerdetails
      end
    end
  end
  
  get '/offer/:offer/comments' do
    begin
      @offer = Offer.get(params[:offer].to_i)
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect back
      end
    end
    @order = Order.get(@offer.order_id)

    @description = @offer.subject + " " + fulllocation(@offer.user)
    @tags = @order.tags.all.map(&:tag).join(', ')

    if !logged_in?
      session[:messagetodisplay] = @@text["notify"]["plsloginforoffercomments"]
      redirect back
    else
      #@questions = Message.all(:offer_id => params[:offer].to_i, :type => "Question")
      @rootquestions = Message.all(:offer_id => params[:offer].to_i, :parent => nil)
      haml :navbarafterlogin do
        haml :offercomments
      end
    end
  end
  
  get '/offer/:offer/newcomments' do
    begin
      @offer = Offer.get(params[:offer].to_i)
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect back
      end
    end
    @order = Order.get(@offer.order_id)

    @description = @offer.subject + " " + fulllocation(@offer.user)
    @tags = @order.tags.all.map(&:tag).join(', ')

    if !logged_in?
      session[:messagetodisplay] = @@text["notify"]["plsloginforoffercomments"]
      redirect back
    else
      #@questions = Message.all(:offer_id => params[:offer].to_i, :type => "Question")
      @rootquestions = Message.all(:offer_id => params[:offer].to_i, :parent => nil)
      haml :navbarafterlogin do
        haml :newoffercomments, :layout => false
      end
    end
  end

  put '/offer/:offer' do
    if !logged_in?
      haml :navbarbeforelogin do
        redirect '/'
      end
    else
      haml :navbarafterlogin do
        offer = Offer.get(params[:offer].to_i)
        if offer.user != current_user || offer.status == 3
          session[:messagetodisplay] = "Вы не можете снять предложение"
          redirect back
        else
          offer.update(:status => 1, :td => DateTime.now)
          session[:messagetodisplay] = @@text["notify"]["offerwasarchvied"]
          redirect back
        end
      end
    end
  end
  
  post '/offer/:offer/startwork' do
    begin
      @offer = Offer.get(params[:offer].to_i)
      if @offer.status != 0
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect '/'
      end
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect '/'
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect '/'
      end
    end
    if !logged_in? || User.get(Order.get(@offer.order_id).user_id) != current_user
      redirect '/'
    else
      if @offer.status != 0
        session[:messagetodisplay] = @@text["notify"]["invalidoffer"]
        redirect back
      end
      @offer.update(:status => 2)
      @order = Order.get(@offer.order_id)
      @order.update(:status => 3)
      int_msg = "Здравствуйте!<br/>Ваше предложение было принято. Пожалуйста, <a href='http://" + request.host + ":" + request.port.to_s + "/offer/" + @offer.id.to_s +  "'>подтвердите</a> свою готовность выполнить работу."
      int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
      if params[:message] && params[:message].size>0
        int_msg += "<br/><br/><mark>Дополнительная информация от заказчика:</mark><br/><blockquote>" + h(params[:message]) + "</blockquote>"
      end
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @offer.user, :type => "Request", :offer => @offer, :order => @order)
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["acceptoffer"] + request.host + ":" + request.port.to_s + "/offer/" + @offer.id.to_s
      if params[:message] && params[:message].size>0
        email_msg += "\nДополнительная информация от заказчика:\n" + params[:message]
      end
      email_msg += @@text["email"]["regards"]
      if get_settings(@offer.user, "sendmessagestoemail")
        Pony.mail(:to => @offer.user.email, :subject => 'Ваше предложение было принято на РемЗона24.ру', :body => email_msg)
      end
      session[:messagetodisplay] = @@text["notify"]["acceptoffer"]
      redirect 'profile'
      #rescue
      #  session[:messagetodisplay] = @contract.errors.values.join("; ")
      #  redirect back
      #end
    end
  end

  post '/offer/:offer/acceptwork' do
    begin
      @offer = Offer.get(params[:offer].to_i)
      #if @offer.status != 0
      #  session[:messagetodisplay] = "Предложения не существует"
      #  redirect back
      #end
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect '/'
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect '/'
      end  
    end
    if !logged_in? || @offer.user != current_user
      session[:messagetodisplay] = "Только автор предложения может его подтвердить"
      redirect '/'
    else
      if @offer.status != 2
        session[:messagetodisplay] = "Предложение еще не принято заказчиком"
        redirect '/'
      end
      @order = Order.get(@offer.order_id)
      @contract = Contract.new(:customer => @order.user, :contractor => current_user, :order => Order.get(@offer.order_id), :date => DateTime.now)
      begin
        @contract.save
      rescue
        session[:messagetodisplay] = @contract.errors.values.join("; ")
        redirect back
      end
      @offer.update(:status => 3)
      @order.update(:status => 1)
      int_msg = "Здравствуйте!<br/>Предложение было подтверждено исполнителем."
      int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @order.user, :type => "Accept", :offer => @offer, :order => @order)
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["confirmoffer"] + request.host + ":" + request.port.to_s + "/user/" + @offer.user_id
      email_msg += @@text["email"]["regards"]
      if get_settings(@order.user, "sendmessagestoemail")
        Pony.mail(:to => @order.user.email, :subject => 'Потверждение начала работ на РемЗона24.ру', :body => email_msg)
      end
      session[:messagetodisplay] = @@text["notify"]["confirmoffer"]
      redirect 'profile'
    end
  end

  post '/offer/:offer/refusework' do
    begin
      @offer = Offer.get(params[:offer].to_i)
      #if @offer.status != 0
      #  session[:messagetodisplay] = "Предложения не существует"
      #  redirect back
      #end
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect back
      end
    end
    if !logged_in? || @offer.user != current_user
      redirect '/'
    else
      if @offer.status != 2
        session[:messagetodisplay] = "Предложение не принято заказчиком"
        redirect back
      end
      @order = Order.get(@offer.order_id)
      @offer.update(:status => 4)
      @order.update(:status => 0)
      int_msg = "Здравствуйте!<br/>К сожалению, предложение было отозвано исполнителем."
      int_msg += "<br/><mark>Причина отзыва, указанная исполнителем:</mark><br/>"
      int_msg += "<blockquote>" + h(params[:refusereason]) + "</blockquote>"
      int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @order.user, :type => "Refuse", :offer => @offer, :order => @order)
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["refuseoffer"] + h(params[:refusereason])
      email_msg += @@text["email"]["regards"]
      if get_settings(@order.user, "sendmessagestoemail")
        Pony.mail(:to => @order.user.email, :subject => 'Отзыв предложения на РемЗона24.ру', :body => email_msg)
      end
      session[:messagetodisplay] = @@text["notify"]["refuseoffer"]
      redirect 'profile'
      #@contract = Contract.new(:customer => User.get(@offer.order).user, :contractor => current_user)
      #begin
      #redirect 'profile'
      #rescue 
      #  session[:messagetodisplay] = @contract.errors.values.join("; ")
      #  redirect back
      #end
    end
  end
  
  get '/message/:id' do
    if !logged_in?
      redirect '/'
    else
      @msg = Message.get(params[:id].to_i)
      if !@msg
        session[:messagetodisplay] = @@text["notify"]["nomessage"]
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = @@text["notify"]["cantreadmessage"]
        redirect back
      end
      @msg.update(:unread => false)
      @order = Order.get(@msg.order_id)
      @offer = Offer.get(@msg.offer_id)
      haml :navbarafterlogin do
        haml :messageview
      end
    end
  end

  put '/message/:id' do
    if !logged_in?
      redirect '/'
    else
      @msg = Message.get(params[:id].to_i)
      if !@msg
        session[:messagetodisplay] = @@text["notify"]["nomessage"]
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = @@text["notify"]["cantarchivemessage"]
        redirect back
      end
      @msg.update(:archived => true)
      session[:messagetodisplay] = @@text["notify"]["messagewasarchived"]
    end
    redirect '/profile'
  end

  delete '/message/:id' do
    if !logged_in?
      redirect '/'
    else
      @msg = Message.get(params[:id].to_i)
      if !@msg
        session[:messagetodisplay] = @@text["notify"]["nomessage"]
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = @@text["notify"]["cantdeletemessage"]
        redirect back
      end
      @msg.destroy
      session[:messagetodisplay] = @@text["notify"]["messagewasdeleted"]
    end
    redirect '/profile'
  end
  
  get '/faq' do
    @faq = @@text["faq"]
    if !logged_in?
      haml :navbarbeforelogin do
        haml :faq
      end
    else
      haml :navbarafterlogin do
        haml :faq
      end
    end
  end
  
    
  get '/terms' do
    @terms = @@terms["terms"]
    if !logged_in?
      haml :navbarbeforelogin do
        haml :terms
      end
    else
      haml :navbarafterlogin do
        haml :terms
      end
    end
  end
    
  get '/support' do
    if !logged_in?
      session[:messagetodisplay] = @@text["notify"]["plsloginforsupport"]
      #puts "********* >>>>", session[:messagetodisplay]
      redirect back
    else
      haml :navbarafterlogin do
        haml :support
      end
    end
  end
  
  post '/support' do
    @message = Message.new(
      :sender => current_user,
      :receiver => User.get(1),
      :unread => true,
      :subject => h(params[:subject]),
      :text => h(params[:question]),
      :date => DateTime.now,
      :type => "Support"
    )
    begin
      @message.save
      session[:messagetodisplay] = @@text["notify"]["messagesent"]
    rescue
      session[:messagetodisplay] = @message.errors.values.join("; ")
    ensure
      redirect '/'
    end
  end
  
  get '/about' do
    @about = @@text["about"]
    if !logged_in?
      haml :navbarbeforelogin do
        haml :about
      end
    else
      haml :navbarafterlogin do
        haml :about
      end
    end
  end

  get '/ajax/tags.json' do
    # tags = Tag.all
    # jsontags = []
    # tags.each do |t|
    #   jsontags << t.tag
    # end
    # JSON.generate(jsontags)

    @tags = Tag.all
    @tagslist = @tags.map do |u|
      { :id => u.id, :tag => u.tag }
    end

    json = { :tags => @tagslist }.to_json
    json
  end
  
  #get '/ajax/vehicle' do
    #url = URI::encode("https://api.edmunds.com/api/vehicle/v2/makes?fmt=json&api_key="+settings.edminds_api)
    #resp = Net::HTTP.get_response(URI.parse(url))
    #vehicles = JSON.parse(resp.body)
    #@vehicles = YAML.load_file("public/makes.yml")
    #puts @@vehicles.class
    #vehicles = JSON.generate(settings.vehicles)
    #puts vehicles.class
    #puts settings.vehicles.class
    #puts vehicles
    #puts settings.vehicles.values
    #vehicles
  #end
  
  post '/ajax/checkemail' do
    if !logged_in?
      if params[:email].nil?
        '"Введите адрес электронной почты"'
      elsif User.first(:email=>params[:email])
        '"Данный адрес электронной почты уже зарегистрирован"'
      else
        "true"
      end
    else
      if params[:email].nil?
        '"Введите адрес электронной почты"'
      elsif User.first(:email=>params[:email]) && @current_user.email != params[:email]
        '"Данный адрес электронной почты уже зарегистрирован"'
      else
        "true"
      end
    end
  end
  
  post '/ajax/checkfullname' do
    if params[:fullname].nil?
      '"Введите полное имя контактного лица"'
    elsif (params[:fullname].match(/^[а-яА-ЯёЁa-zA-Z- ]+$/)).nil?
      '"Полное имя может содержать только буквы и пробел"'
    else
      "true"
    end
  end

  post '/ajax/checkfamilyname' do
    if params[:familyname].nil?
      '"Введите фамилию контактного лица"'
    elsif (params[:familyname].match(/^[а-яА-ЯёЁa-zA-Z-]+$/)).nil?
      '"Фaмилия может содержать только буквы"'
    else
      "true"
    end
  end
  
  post '/ajax/checkfathersname' do
    if params[:fathersname].nil?
      '"Введите отчество контактного лица"'
    elsif (params[:fathersname].match(/^[а-яА-ЯёЁa-zA-Z-]+$/)).nil?
      '"Отчество может содержать только буквы"'
    else
      "true"
    end
  end
    
  post '/ajax/checkname' do
    if params[:name].nil?
      '"Введите имя контактного лица"'
    elsif (params[:name].match(/^[а-яА-ЯёЁa-zA-Z-]+$/)).nil?
      '"Имя может содержать только буквы"'
    else
      "true"
    end
  end
  
  post '/ajax/checkphone' do
    if params[:phone].nil?
      '"Введите мобильный телефонный номер"'
    elsif (params[:phone].match(/^((8|\+7)\d{10}$)/)).nil?
      '"Номер должен начинатся с +7 или 8 и затем содержать 10 цифр"'
    else
      "true"
    end
  end

  post '/ajax/checkpass' do
    if params[:password] != params[:pass]
      '"Ошибка при повторном вводе пароля"'
    else
      "true"
    end
  end
  
  post '/ajax/checklocation' do
    fulllocation = params[:locationtitle] + (params[:area].size > 0 ? ", " + params[:area] : "") + (params[:region].size > 0 ? ", " + params[:region] : "")
    if params[:fulllocation] != fulllocation
      '"Выберите населенный пункт из списка"'
    else
      "true"
    end
  end
  
  post '/ajax/checkmakes' do
    "true"
  end

  post '/auth/login' do
    env['warden'].authenticate!
    redirect back
  end

  post '/auth/unauthenticated' do
    redirect '/'
  end

  ["/auth/sign_out/?", "/auth/signout/?", "/auth/log_out/?", "/auth/logout/?"].each do |path|
    get path do
      env['warden'].raw_session.inspect
      env['warden'].logout
      puts "LOGOUT!!!"
      session[:user_id] = nil
      #session[:messagetodisplay] = "Вы вышли из системы"
      session[:messagetodisplay] = @@text["notify"]["logout"]
      redirect '/'
    end
  end

  not_found do
    session[:messagetodisplay] = @@text["notify"]["404"] if !session[:messagetodisplay]
    redirect '/'
  end

  get '/promo4users' do
    if !logged_in?
      haml :navbarbeforelogin do
        haml :promo4users
      end
    else
      redirect '/'
    end
  end

end

#Remzona24App.run!