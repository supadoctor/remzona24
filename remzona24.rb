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

class Remzona24App < Sinatra::Application
  #register Sinatra::Subdomain
  set :environment, :production
  use Rack::Session::Cookie, :key => "rack.session", :expire_after => 31557600, :secret => "nothingintheinternetissecret"
#  configure :production do
#    set :port => 8888, :bind => '46.254.20.57'
#  end

#  configure :test do
#    #set :port => 8888, :bind => '0.0.0.0'
#    set :port => 8888, :bind => '46.254.20.57'
#  end

  configure do
    enable :logging, :method_override
    I18n.enforce_available_locales = false
    CarrierWave::SanitizedFile.sanitize_regexp = /[^[:word:]\.\-\+]/
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
    :from => 'Ремзона24.ру <robot@remzona24.ru>',
    :charset => 'utf-8',
    :via => :sendmail
  }
#  Pony.mail(:to => 'sergey.rodionov@gmail.com', :subject => 'Запуск РемЗона24.ру', :body => 'Thin был запущен')

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
        begin
          user.update(:lastlogon => DateTime.now)
        rescue
          puts "Error on logon time updating:", user.errors.values
        end
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
        begin
          user.update(:lastlogon => DateTime.now)
        rescue
          puts "Error on logon time updating:", user.errors.values
        end
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
      if v
        (v.make && v.make.size > 0 ? v.make : "") + (v.mdl && v.mdl.size > 0 ? " " + v.mdl : "") + (v.year && v.year>0 ? ", год выпуска: " + v.year.to_s : "") + (v.VIN && v.VIN.size > 0 ? ", VIN: " + v.VIN : "")
      else
         return "нет информации"
      end
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
      if l > 5
	k = 5
      else
	k = l
      end
      haml_tag :div,:class=>"uk-width-5-10 uk-push-#{k}-10" do
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
	    if msg.receiver == current_user
	      haml_tag :div, :class=>"uk-align-right uk-text-small uk-margin-bottom-remove" do
	        haml_tag :a, :href=>"/message/"+msg.id.to_s do
                  haml_concat "Ответить"
		  haml_tag :i, :class=>"uk-icon-angle-double-right"
                end
	      end
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
              haml_tag :i, :class=>"uk-icon-comment", :title=>"Предложения"#, data: {"uk-tooltip": ""}
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
                c = Offer.count(:order_id => o.id)
                if c > 0
                  haml_tag :div, :class=>"uk-badge uk-badge-warning" do
                    haml_concat c
                  end
                else
                  haml_concat c
                end
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

  def showoffercount(o)
    c = Offer.count(:order_id => o.id)
    if c > 0
      haml_tag :div, :class=>"uk-badge uk-badge-warning" do
        haml_concat c
      end
    else
      haml_concat c
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
                  if m.subject.to_s.size == 0
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

  def brand(arg)
    showbrand = true
    case arg
    when "Acura"
      d = 0
    when "Alfa Romeo"
      d = -29*1
    when "Aston Martin"
      d = -29*2
    when "Audi"
      d = -29*3
    when "BMW"
      d = -29*5
    when "Bentley"
      d = -29*4
    when "Cadillac"
      d = -29*6
    when "Chevrolet"
      d = -29*7
    when "Chrysler"
      d = -29*8
    when "Citroen"
      d = -29*9
    when "Daewoo"
      d = -29*10
    when "Dodge"
      d = -29*11
    when "Ferrari"
      d = -29*12
    when "Fiat"
      d = -29*13
    when "Ford"
      d = -29*14
    when "Honda"
      d = -29*15
    when "Hummer"
      d = -29*16
    when "Hyundai"
      d = -29*17
    when "Infiniti"
      d = -29*18
    when "Jaguar"
      d = -29*19
    when "Jeep"
      d = -29*20
    when "Kia"
      d = -29*21
    when "Lada (ВАЗ)"
      d = -29*46
    when "Lamborghini"
      d = -29*22
    when "Land Rover"
      d = -29*23
    when "Lexus"
      d = -29*24
    when "MINI"
      d = -29*28
    when "Maserati"
      d = -29*25
    when "Mazda"
      d = -29*26
    when "Mercedes-Benz"
      d = -29*27
    when "Mitsubishi"
      d = -29*29
    when "Nissan"
      d = -29*30
    when "Opel"
      d = -29*31
    when "Peugeot"
      d = -29*32
    when "Porsche"
      d = -29*33
    when "Renault"
      d = -29*34+2
    when "Rolls-Royce"
      d = -29*35
    when "Saab"
      d = -29*36
    when "Scion"
      d = -29*43
    when "Seat"
      d = -29*37
    when "Skoda"
      d = -29*38
    when "Smart"
      d = -29*39
    when "SsangYong"
      d = -29*40
    when "Subaru"
      d = -29*41
    when "Suzuki"
      d = -29*42
    when "Toyota"
      d = -29*43
    when "Volkswagen"
      d = -29*44
    when "Volvo"
      d = -29*45
    when "УАЗ"
      d = -29*47
    when "Chery"
      d = -29*48
    when "Lifan"
      d = -29*49
    when "ГАЗ"
      d = -29*50
    when "Tagaz (ТагАЗ)"
      d = -29*51
    when "ZAZ (ЗАЗ)"
      d = -29*52
    when "Geely"
      d = -29*53
    when "Great Wall"
      d = -29*54
    else
      showbrand = false
    end
    if showbrand
      haml_tag :div, :class => "brand", :style => "background-position: -6px #{d-2}px;"
    end
  end

  def descriptiontag(desc)
    if desc
      haml_tag :meta, {:content=>desc, :name=>"description"}
    else
      haml_tag :meta, {:content=>"Круглосуточный интернет-сервис Ремозона24 осуществляет помощь тем, кому нужен ремонт автомобиля, здесь можно бесплатно оставить свою заявку или заказ наряд на ремонт для автосервиса, доступные цены, удобный поиск автомастерских по ремонту иномарок и отечественных авто", :name=>"description"}
    end
  end

  def keywordstag(tags)
    if tags && tags.size > 0
      haml_tag :meta, {:content=>tags, :name=>"keywords"}
    else
      haml_tag :meta, {:content=>"круглосуточный сервис, сервис круглосуточно, ремонт автомобиля, автомастерская, ремзона, авто ремонт, ремозона24, автосервис, ремонт иномарки, цены на авторемонт, ремзона24.ру, remzona, remzona24, remzona24.ru", :name=>"keywords"}
    end
  end

  def titletag(title)
    if title && title.size > 0
      haml_tag :title do
        haml_concat title
      end
    else
      haml_tag :title do
        haml_concat "Ремзона24.ру : онлайн ремзона, открытая круглые сутки! Бесплатно. Разместите заявку и выберите лучшее предложение от автомастеров, автосервисов или СТО."
      end
    end
  end

  def showlastmasters
    o = User.all(:type => "Master", :status => 0).count - 3
    lastmasters = User.all(:type => "Master", :offset => o, :limit => 3, :status => 0)
    k = 0
    lastmasters.reverse_each do |m|
      k += 1
      haml_tag :div, :class => "uk-panel" do #"uk-panel uk-panel-box uk-margin-bottom masteratmainpage"
        haml_tag :div, :class => "uk-panel-box uk-margin-bottom", :id => "mastercard#{k}" do
          haml_tag :div, :class => "front" do
            haml_tag :div, :class => "uk-grid" do
              haml_tag :div, :class => "uk-width-1-3" do
                if m.avatar.present?
                  haml_tag :img, :class => "uk-border-circle", :src => m.avatar.avatar64.url
                else
                  haml_tag :img, :class => "uk-border-circle", :src => "/no_avatar64.gif"
                end
              end
              haml_tag :div, :class => "uk-width-2-3" do
                haml_tag :h3, :class => "uk-text-left" do
                  haml_tag :a, :href => "/user/#{m.id}" do
                    haml_concat m.displayedname
                  end
                end
              end
              haml_tag :div, :class => "uk-width-1-1 uk-text-left" do
                haml_tag :dl, :class =>"uk-description-list uk-description-list-horizontal masters-description-list" do
                  haml_tag :dt, "Расположение:"
                  haml_tag :dd, :class => "uk-text-small" do
                    haml_concat fulllocation(m)
                  end
                  # if m.description.to_s.size > 0
                  #   haml_tag :dt, "Описание:"
                  #   haml_tag :dd, :class =>"uk-text-justify" do
                  #     haml_concat shortdescription(m.description)
                  #   end
                  # end
                  haml_tag :dt, "На сайте с:"
                  haml_tag :dd, :class => "uk-text-small" do
                    haml_concat m.created_at.strftime("%d.%m.%Y")
                  end
                end
              end
              haml_tag :div, :class => "uk-align-right uk-text-small uk-margin-bottom-remove" do
                haml_tag :a, :href => "/user/#{m.id}" do
                  haml_concat "Подробнее"
                  haml_tag :i, :class => "uk-icon-angle-double-right"
                end
              end
            end
          end
          # if m.description.to_s.size > 0
          #   haml_tag :div, :class => "back" do
          #     haml_tag :div, :class => "uk-width-1-1 uk-text-left" do
          #       haml_tag :dl, :class =>"uk-description-list uk-description-list-horizontal masters-description-list" do
          #         haml_tag :dt, "Описание:"
          #         haml_tag :dd, :class =>"uk-text-justify" do
          #           haml_concat shortdescription(m.description)
          #         end
          #       end
          #     end
          #   end
          # end
        end
      end
    end
  end

    def current_timestamp
      DateTime.now.to_time.to_i
    end

    def shortdescription(d)
      if d.length > 155
        d[0..155]+"..."
      else
        d
      end
    end

    def orderhaspicture?(order)
      p = Orderimage.all(:order_id => order.id)
      if p.count > 0
        return true
      else
        return false
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
    @end_page = @start_page + 9
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 9) > 0 ? (@end_page - 9) : 1
    end
    @pagination = @start_page..@end_page
    #puts "***********", "CP:", @current_pagem, "TP:", @total_pages, "SP:", @start_page, "EP", @end_page, "**********"

    #@orders_at_mainpage = (Order.all(:status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)
    #@new_orders_at_mainpage = @orders_at_mainpage
    #@description = "база данных заявок на ремонт автомобилей, автомастеров и СТО. бесплатно разместить объявление о ремоте авто, найти заказ подряд на ремонт авто"
    if !logged_in?
      #puts "БЕЗ АУТЕТНИФИКАЦИИ"
      if !session[:siteregionplaceholder]
        session[:siteregionplaceholder] = "Россия"
      end
      haml :navbarbeforelogin do
        haml :index, :layout => :promo
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
    if @showmastersinlocation.to_s.size == 0
      @masters_at_mainpage_total = User.all(:status => 0, :type => "Master", :order => [ :lastlogon.desc ]).count
      @masters_at_mainpage = User.all(:status => 0, :type => "Master", :order => [ :lastlogon.desc ]).paginate(:page => params[:page], :per_page => 10)
    elsif
      @masters_at_mainpage_total = User.all(:status => 0, :type => "Master", :placement => {:location => @showmastersinlocation}, :order => [:lastlogon.desc]).count
      @masters_at_mainpage = User.all(:status => 0, :type => "Master", :placement => {:location => @showmastersinlocation}, :order => [:lastlogon.desc]).paginate(:page => params[:page], :per_page => 10)
    end
    if params[:page].nil?
      @current_page = 1
    else
      @current_page = params[:page].to_i
    end
    @total_pages = (@masters_at_mainpage_total/10.0).ceil
    @total_pages = @total_pages > 0 ? @total_pages : 1
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 9

    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 9) > 0 ? (@end_page - 9) : 1
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

    @description = "База мастеров по ремонту автомобилей, СТО, автосервисов"
    @description += "в " + @showmastersinlocation if @showmastersinlocation
    @tags = "автомастер, СТО, найти матера по ремонту авто, отзыв о автомастере"
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

  get '/mastersmap' do
    if params[:splat]
      if params[:splat][0].size > 0
        @territory = params[:splat][0]
      end
    end
    #myterritory = Placement.all(:region => @territory
    @uniqlocations = User.all(:status => 0, :fields => [:id, :placement_id], :type=>"Master", :unique => true)
    @mastersbylocation = {}
    @uniqlocations.each do |l|
      count = User.all(:status => 0, :type => "Master", :placement_id => l.placement_id).count
      if count > 0
        place = Placement.get(l.placement_id)
        fullplace = place.location.to_s + place.area.to_s + place.region.to_s
        @mastersbylocation.merge!(fullplace => count)
      end
    end
    #puts @mastersbylocation.size
    if !logged_in?
      haml :navbarbeforelogin do
        haml :mastersmap
      end
    else
      haml :navbarafterlogin do
        haml :mastersmap
      end
    end
  end

  get '/region/:region' do
    @activelink = '/region'
    if params[:page].nil?
      @current_page = 1
    else
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage_total = (Order.all(:placement => {:region => params[:region]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).count
    @orders_at_mainpage = (Order.all(:placement => {:region => params[:region]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)

    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 9
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 9) > 0 ? (@end_page - 9) : 1
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
      @current_page = 1
    else
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage_total = (Order.all(:placement => {:area => params[:area]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).count
    @orders_at_mainpage = (Order.all(:placement => {:area => params[:area]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)

    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 10
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 9) > 0 ? (@end_page - 9) : 1
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
      @current_page = 1
    else
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage_total = (Order.all(:placement => {:location => params[:location]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).count
    @orders_at_mainpage = (Order.all(:placement => {:location => params[:location]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))).paginate(:page => params[:page], :per_page => 10)

    @total_pages = (@orders_at_mainpage_total/10.0).ceil
    @start_page  = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    @end_page = @start_page + 9
    if @end_page > @total_pages
      @end_page = @total_pages
      @start_page = (@end_page - 9) > 0 ? (@end_page - 9) : 1
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
      :avatar => File.open("public/no_avatar.gif"),
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
      #:fathersname => Unicode::capitalize(params[:fathersname]),
      :created_at => DateTime.now,
      :password => params[:password],
      :placement => placement,
      :status => 0,
      :adstatus => 0,
      :avatar => File.open("public/no_avatar.gif"),
      :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
    begin
      user.save
    rescue
      session[:messagetodisplay] = user.errors.values.join("; ")
      redirect back
    end
    session[:user_id] = user.id
    @msg = "Здравствуйте, " + user.displayedname + "!\n" + @@text["email"]["masterregistration"] + @@text["email"]["regards"]
    Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
    env['warden'].authenticate!
    redirect '/masterguide'
  end

  get '/masterguide' do
    if !logged_in? || current_user.type != "Master"
      haml :navbarbeforelogin do
        redirect '/'
      end
    else
      haml :navbarafterlogin do
        haml :masterguide
      end
    end
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
            @myclosedoffers = Offer.all(:user => current_user, :order => [ :fd.desc ]) & (Offer.all(:status => 1, :order => [ :fd.desc ]) | Offer.all(:status => 4, :order => [ :fd.desc ]) | Offer.all(:status => 5, :order => [ :fd.desc ]) | Offer.all(:conditions => ['fd <> td'], :td.lt => DateTime.now, :order => [ :fd.desc ]))
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

  get '/user/:id', :agent => /(YandexBot\/\w+)|(Googlebot\/\w+)/ do
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
    else
      redirect back
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

  post '/firstupdateprofile' do
    user = current_user
    begin
      if params[:description].to_s.size > 0
        user.update(:description => h(params[:description]))
      end
      if params[:tags].to_s.size > 0
        tagsstring = params[:tags]
        newtags = []
        tagsstring.split(",").each do |t|
          #tag = @current_user.tags.first_or_create(:tag => t.strip)
          newtags << Tag.first_or_create(:tag => t.strip)
        end
        user.tags = newtags
        user.save
      end
      if params[:avatar]
        user.update(:avatar => params[:avatar])
      end
    rescue
      session[:messagetodisplay] = user.errors.values.join("; ")
      redirect '/profile'
    end
    redirect '/'
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
          @current_user.update(:name => params[:name], :fathersname => params[:fathersname], :familyname => params[:familyname], :description => h(params[:description]), :servicename => h(params[:servicename]), :www => params[:www], :phone => params[:phone], :email => params[:email], :placement => placement)
          if params[:avatar] && !params[:delete_avatar]
            @current_user.update(:avatar => params[:avatar])
          end
          if params[:banner] && !params[:delete_banner]
            @current_user.update(:banner => params[:banner])
            #puts ">>BANNER", @current_user.banner.present?
          end
          if params[:pricelist] && !params[:delete_pricelist]
            @current_user.update(:pricelist => params[:pricelist])
          end
          if params[:delete_avatar]
            @current_user.update(:avatar => nil)
          end
          if params[:delete_banner]
            @current_user.update(:banner => nil)
          end
          if params[:delete_pricelist]
            @current_user.update(:pricelist => nil)
          end
          oldtags = @current_user.usertaggings
          oldtags.each {|ot| ot.destroy }
          tagsstring = params[:tags]
          newtags = []
          tagsstring.split(",").each do |t|
            #tag = @current_user.tags.first_or_create(:tag => t.strip)
            newtags << Tag.first_or_create(:tag => t.strip)
          end
          @current_user.tags = newtags
          @current_user.save
        rescue
          puts "Error in updating user's profile"
          session[:messagetodisplay] = @current_user.errors.values.join("; ")
          session[:messagetodisplay] = "Размер баннера должен быть 728х90 пикселей" if session[:messagetodisplay].length == 0
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

  get '/resetpassword' do
    if !logged_in?
      haml :navbarbeforelogin do
        haml :resetpassword
      end
    else
      redirect back
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
    if params[:mapx].to_f > 0 && params[:mapy].to_f > 0
      @current_user.update(:mapx => params[:mapx].to_f, :mapy => params[:mapy].to_f)
    else
      session[:messagetodisplay] = @@text["notify"]["checkmap"]
    end
    redirect back
  end

  post '/updatesettings' do
    current_user
    session[:activetab] = "settings"
    settings_list = ["showemail", "showphone", "sendmessagestoemail", "subscribed"]
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

  get '/order/:id/edit' do
    if !logged_in?
      redirect '/'
    else
      begin
        @order = Order.get(params[:id].to_i)
      rescue
        session[:messagetodisplay] = @@text["notify"]["noorder"]
        redirect back
      ensure
        if @order.nil? || @order.status == 2
          session[:messagetodisplay] = @@text["notify"]["noorder"]
          redirect back
        end
      end
      if @order.user == current_user
        if Offer.all(:order_id => params[:id].to_i, :status => 0).count == 0
          @tags = []
          @order.tags.all.each do |t|
            @tags << t.tag
          end
          @tags = @tags.join(', ')
          @lifetime = (@order.td - @order.fd).ceil
          haml :navbarafterlogin do
            haml :editorder
          end
        else
          session[:messagetodisplay] = @@text["notify"]["canteditorder"]
          redirect '/'
        end
      else
        session[:messagetodisplay] = @@text["notify"]["canteditorder"]
        redirect '/'
      end
    end
  end

  post '/order/:id/edit' do
    if !logged_in?
      redirect '/'
    else
      begin
        @order = Order.get(params[:id].to_i)
      rescue
        session[:messagetodisplay] = @@text["notify"]["noorder"]
        redirect back
      ensure
        if @order.nil? || @order.status == 2
          session[:messagetodisplay] = @@text["notify"]["noorder"]
          redirect back
        end
      end
      if @order.user == current_user
        fd = DateTime.now
        td = fd+params[:lifetime].to_i
        if params[:budgettype] == "1"
          budget = -1
        else
          budget = params[:budget].to_i
        end
        begin
          @order.update(
            :title => h(params[:title]),
            :subject => h(params[:subject]),
            :budget => budget,
            :status => 0,
            :fd => fd,
            :td => td)
          @order.vehicle.update(:make => params[:vehiclemake], :mdl => h(params[:vehiclemodel]), :year => params[:vehicleyear].to_i, :VIN => h(params[:vehicleVIN]))
        rescue
          session[:messagetodisplay] = @order.errors.values.join("; ") + @order.vehicle.errors.values.join("; ")
          redirect back
        end
        tagsstring = params[:tags]
        newtags = []
        tagsstring.split(",").each do |t|
          #tag = @order.tags.first_or_create(:tag => t.strip)
          newtags << Tag.first_or_create(:tag => t.strip)
        end
        @order.tags = newtags
        @order.save
        if params[:photos] && !params[:photos].empty?
          params[:photos].each do |image|
            begin
              oi = Orderimage.create(:order => @order, :image => image)
            rescue
              session[:messagetodisplay] = oi.errors.values.join("; ")
              redirect back
            end
          end
        end
        session[:messagetodisplay] = @@text["notify"]["orderwasedited"]
        redirect '/order/'+@order.id.to_s
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
    newtags = []
    tagsstring.split(",").each do |t|
      #tag = order.tags.first_or_create(:tag => t.strip)
      newtags << Tag.first_or_create(:tag => t.strip)
    end
    order.tags = newtags
    order.save
    #puts "Кол-во фоток: ", params[:photos].size
    if  params[:photos] && !params[:photos].empty?
      params[:photos].each do |image|
        begin
          oi = Orderimage.create(:order => order, :image => image)
        rescue
          session[:messagetodisplay] = oi.errors.values.join("; ")
          redirect back
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
    h(params[:subject]).size > 50 ? t = h(params[:subject])[0..46]+'...' : t = h(params[:subject])[0..49]
    order = Order.new(
      :user => user,
      #:title => h(params[:title]),
      :title => t,
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
    email_msg = @@text["email"]["newoffer"] + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "\n\nСсылка на исходную заявку: http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + @@text["email"]["regards"]
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
      end
      email_msg = @@text["email"]["unreadnotification"] + @@text["email"]["regards"]
      if get_settings(@order.user, "sendmessagestoemail")
        Pony.mail(:to => @offer.user.email, :subject => 'Непрочитанное уведомление на РемЗона24.ру', :body => email_msg)
      end
      redirect back
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
      #else
      #  @order = Order.get(Offer.get(params[:offer].to_i).order_id)
      #  @message = Message.new(
      #   :sender => current_user,
      #   :receiver => @order.user,
      #      :offer => @offer,
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
        redirect back
      end
      email_msg = @@text["email"]["unreadnotification"] + @@text["email"]["regards"]
      if get_settings(@offer.user, "sendmessagestoemail")
        Pony.mail(:to => @offer.user.email, :subject => 'Непрочитанное уведомление на РемЗона24.ру', :body => email_msg)
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
    @title = "www.remzona24.ru " + @order.title

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
    rescue
      session[:messagetodisplay] = @@text["notify"]["nooffer"]
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = @@text["notify"]["nooffer"]
        redirect back
      end  
    end
    if !logged_in?
      session[:messagetodisplay] = @@text["notify"]["plsloginforoffer"]
      redirect back
    else
      @order = Order.get(@offer.order_id)
      if @order.user == current_user
        @offer.update(:unread => false)
      end
      @description = @offer.subject + " " + fulllocation(@offer.user)
      @tags = @order.tags.all.map(&:tag).join(', ')
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
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @offer.user, :type => "Accept", :subject => nil)
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

  post '/offer/:offer/refuseoffer' do
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
      @offer.update(:status => 5)
      @order = Order.get(@offer.order_id)
      #@order.update(:status => 3)
      int_msg = "Здравствуйте!<br/>Ваше предложение было отклонено."
      int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
      if params[:message] && params[:message].size>0
        int_msg += "<br/><br/><mark>Дополнительная информация от заказчика:</mark><br/><blockquote>" + h(params[:message]) + "</blockquote>"
      end
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @offer.user, :type => "Refuse", :subject => nil)
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["customerrefuseoffer"]
      if params[:message] && params[:message].size>0
        email_msg += "\nДополнительная информация от заказчика:\n" + params[:message]
      end
      email_msg += @@text["email"]["regards"]
      if get_settings(@offer.user, "sendmessagestoemail")
        Pony.mail(:to => @offer.user.email, :subject => 'Ваше предложение было отклонено на РемЗона24.ру', :body => email_msg)
      end
      session[:messagetodisplay] = @@text["notify"]["customerrefuseoffer"]
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
      if params[:message] && params[:message].size>0
        int_msg += "<br/><br/><mark>Дополнительная информация от исполнителя:</mark><br/><blockquote>" + h(params[:message]) + "</blockquote>"
      end
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @order.user, :type => "Accept", :subject => nil)
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = @@text["email"]["confirmoffer"] + request.host + ":" + request.port.to_s + "/user/" + @offer.user_id.to_s
      if params[:message] && params[:message].size>0
        email_msg += "\nДополнительная информация от исполнителя:\n" + params[:message]
      end
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
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @order.user, :type => "Refuse", :subject => nil)
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
      Pony.mail(:to => 'sergey.rodionov@gmail.com', :subject => 'Запрос поддержки на РемЗона24.ру', :body => 'Вам был направлен новый запрос на поддержку')
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

  get '/news' do
    @news = @@text["news"]
    if !logged_in?
      haml :navbarbeforelogin do
        haml :news
      end
    else
      haml :navbarafterlogin do
        haml :news
      end
    end
  end

  get '/express' do
    if !logged_in?
      haml :navbarbeforelogin do
        haml :express
      end
    else
      haml :navbarafterlogin do
        redirect '/profile'
      end
    end
  end

  get '/ajax/tags.json' do
    content_type :json
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

  get '/ajax/mastersdata.json' do
    content_type :json
    uniqlocations = User.all(:status => 0, :fields => [:id, :placement_id], :type=>"Master", :unique => true)
    masters = User.all(:status => 0, :type=>"Master")
    data = {:type => "FeatureCollection", :features => []}
    id = 0
    masters.each do |m|
      #count = User.all(:status => 0, :type => "Master", :placement_id => l.placement_id).count
      #if count > 0
        place = Placement.get(m.placement_id)
        if m.mapx.nil? || m.mapy.nil?
          fullplace = place.location.to_s + ", " + place.area.to_s + ", " + place.region.to_s
          #geocoderesp = Net::HTTP.get_response(URI.parse(URI.encode("http://geocode-maps.yandex.ru/1.x/?geocode=" + fullplace)))
          xml = Nokogiri::XML(open(URI.parse(URI.encode("http://geocode-maps.yandex.ru/1.x/?geocode=" + fullplace))))
          coords = xml.css("GeoObject").first.last_element_child.last_element_child.inner_text
          c = []
          c << coords.split(" ")[1].to_f
          c << coords.split(" ")[0].to_f
        else
          c = [m.mapx, m.mapy]
        end
        #xml.root.elements.each do |node|
        # puts ">>>>>>>>>>>>", node.class, node
        #end
        data[:features][id] = {
          :type => "Feature",
          :id => id,
          :geometry  => {:type => "Point", :coordinates => c},
          :properties => {:clusterCaption => "Мастер", :balloonContent => m.displayedname + '</br><a href="/user/'+m.id.to_s+'">Подробнее</a>', :hintContent => m.description}
          #:properties => {:clusterCaption => "Мастер", :balloonContentBody => m.description, :balloonContentHeader => m.displayedname, :balloonContentFooter => '<a href="/user/"'+m.id_to_s+'">Подробнее></a>', :hintContent => m.displayedname}
        }
      id += 1
      #end
    end
    puts JSON.generate(data)
    data.to_json
  end

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
      params[:key] ? @adkeyword = "Требуется " + params[:key] + "?" : @adkeyword = ""
      haml :navbar4promo do
        haml :promo4userscore, :layout => :promo4users
      end
    else
      redirect '/'
    end
  end

  get '/forusers' do
    if !logged_in?
      haml :navbarbeforelogin do
        haml :promo4userscore
      end
    else
      redirect '/'
    end
  end


  get '/promo4masters' do
    if !logged_in?
      session[:showmainpage] = true
      haml :navbar4promo do
        haml :promo4masterscore, :layout => :promo4masters
      end
    else
      redirect '/'
    end
  end

  get '/formasters' do
    if !logged_in?
      haml :navbarbeforelogin do
        haml :promo4masterscore
      end
    else
      redirect '/'
    end
  end


  get '/system/cron' do
    #Send notifications about unread offers
    unreadoffers = Offer.all(:fields => [:id, :order_id], :unread =>true, :unique => true, :order => [:order_id.asc], :fd.gte => DateTime.now-7)
    unreadoffers.each do |o|
      order = Order.get(o.order_id)
      @email = User.get(order.user_id).email
      email_msg = @@text["email"]["youhaveunreadoffers"] + "http://" + request.host + ":" + request.port.to_s + "/offer/" + o.id.to_s
      email_msg += "\n\nСсылка на исходную заявку: http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + @@text["email"]["regards"]
      if get_settings(order.user, "sendmessagestoemail")
        Pony.mail(:to => @email, :subject => 'По вашей заявке есть предложение, с которым вы еще не ознакомились', :body => email_msg)
        puts "Отправлено сообщение о непрочитанном предложении на адрес: ", @email
      end
    end

    #Send notifications about new orders
    @allmasters = User.all(:status => 0, :type => "Master")
    @allmasters.each do |m|
      if get_settings(m, "sendmessagestoemail")
        allorders = Order.all(:status => 0, :placement_id => m.placement_id, :order => [ :fd.desc ]) & (Order.all(:fd.gte => DateTime.now-7, :order => [ :fd.desc ]))
        if allorders.count > 0
          email_msg = "Здравствуйте, " + m.displayedname + "!\n\nЗа прошедшую неделю в вашем регионе были добавлены следующие новые заказ наряды:\n"
          allorders.each do |o|
            email_msg += "\nАвтомобиль: " + vehicleinfo(o)
            email_msg += "\nОписание: " + o.subject
            email_msg += "\nПодробнее: http://" + request.host + ":" + request.port.to_s + "/order/" + o.id.to_s
            email_msg += "\n"
          end
          email_msg += "\nПодайте свое предложение первым из автомастеров!"
          email_msg += @@text["email"]["regards"]
          Pony.mail(:to => m.email, :subject => 'Новые заказ наряды в вашем регионе на Ремзона24.ру', :body => email_msg)
          #puts email_msg
          puts "Отправлено сообщение о новых заявках на адрес: ", m.email
        end
      end
    end

    #Send notification to users how to promote their orders
    @allorder = Order.all(:status => 0, :fd.gte => DateTime.now-7, :fd.lt => DateTime.now-1)
    @allorder.each do |o|
      if Offer.count(:order_id => o.id) == 0
        u = User.get(o.user_id)
        if get_settings(u, "subscribed")
          email_msg = "Здравствуйте, " + u.displayedname + "!\n\nЕще раз спасибо что вы воспользовались сервисом Ремзона24.ру и разместили на нем свою заявку! Однако мы обратили внимание, что за прошедшую неделю по вашей заявке не было сделано ни одного предложения от автомастеров. Мы очень хотим помочь вам и поэтому подготовили несколько простых советов:\n"
          email_msg += "1. Проверьте еще раз описание заявки. Достаточно ли в нем информации для автомастера? Очень часто высококлассные мастера не откликаются на малоинформативные заявки, т.к. не хотят терять свое время на уточнение деталей. Сделайте описание своей заявки максимально информативным!\n"
          email_msg += "2. Укажите бюджет для заявки. Деньги - хороший стимул для привлечения внимания мастеров!\n"
          email_msg += "3. Поделитесь своей заявкой в ваших любимых социальных сетях. Кто знает, может среди знакомых ваших знакомых как раз есть нужный вам специалист?\n"
          email_msg += "\n Просмотреть и отредактировать заявку вы сможете по этой ссылке: http://" + request.host + ":" + request.port.to_s + "/order/" + o.id.to_s
          email_msg += @@text["email"]["regards"]
          Pony.mail(:to => u.email, :subject => 'Наши рекомендации по заявке на Ремзона24.ру', :body => email_msg)
          #puts email_msg
          puts "Отправлено сообщение с советами по заявке на адрес: ", u.email
        end
      end
    end
  end

  get '/system/monthlycron' do
    #Send monthly notifications about comeback
    @allmasters = User.all(:status => 0, :type => "Master")
    @allmasters.each do |m|
      if get_settings(m, "subscribed") && (DateTime.now - m.lastlogon) > 30
        allorders = Order.all(:status => 0, :placement_id => m.placement_id)
        if allorders.count > 4
          email_msg = "Здравствуйте, " + m.displayedname + "!\n\nВот уже более месяца вы не заходили на сайт http://www.remzona24.ru. Между тем на Ремзона24.ру много новых заказ-нарядов, которые ждут ваших предложений... Возвращайтесь!\n\nЕсли вы вдруг забыли свой пароль, то воспользуйтесь функцией сброса пароля - http://www.remzona24.ru/resetpassword. А если у вас есть вопрос или предложение по работе сайта - напишите нам здесь http://www.remzona24.ru/support"
          email_msg += @@text["email"]["regards"]
          Pony.mail(:to => m.email, :subject => 'Возвращайтесь на Ремзона24.ру', :body => email_msg)
          #puts email_msg
          puts "Отправлено сообщение про возврат на адрес: ", m.email
        end
      end
    end

  end

  get '/system/checkemail' do
    Pony.mail(:to => 'sergey.rodionov@gmail.com', :subject => 'Тестовое письмо от Ремзона.24', :body => "Ремзона24.ру работает по адресу: "+request.host + ":" + request.port.to_s)
  end

end
#Remzona24App.run!