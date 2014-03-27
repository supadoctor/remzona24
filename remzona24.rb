# encoding: utf-8
require 'rubygems'
require 'bundler'
require 'sinatra'
require 'haml'
require 'bcrypt'
require 'data_mapper'
# require 'keepass/password'
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

require './models.rb'

class Remzona24App < Sinatra::Base
  register Sinatra::Subdomain
  
  configure do
    set :port => 8888, :bind => '0.0.0.0'
    enable :sessions, :logging, :method_override
    I18n.enforce_available_locales = false
  end    
    #@text = YAML.load_file("public/texts.yml")
    #puts @text["hints"]["email"]
    
    # use Rack::Session::Cookie, secret: "rem_zona_24_ru_secret"

  Pony.options = {
    :from => 'noreply@remzona24.ru',
    :via => :smtp,
    :charset => 'utf-8',
    :via_options => {
      :address => 'smtp.gmail.com',
      :port => '587',
      :enable_starttls_auto => true,
      :user_name => 'sergey.rodionov@gmail.com',
      :password => 'Neverfoget1',
      :authentication => :login, # :plain, :login, :cram_md5, no auth by default
      :domain => "localhost.localdomain" # the HELO domain provided by the client to the server
    }
  }

  use Warden::Manager do |config|
    # config.default_strategies :password, action: 'auth/unauthenticated'
    config.failure_app = self
    config.serialize_into_session{|user| user.id }
    config.serialize_from_session{|id| User.get(id) }

    config.scope_defaults :default,
      strategies: [:password],
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
        session[:messagetodisplay]= "Неверное имя пользователя или пароль."
      elsif user.authenticate(params["password"])
        user.update(:lastlogon => DateTime.now)
        success!(user)
      else
        session[:messagetodisplay]= "Неверное имя пользователя или пароль."
      end
    end
  end

  helpers do
    def current_user
      # @current_user ||= User.get(session[:user_id]) if session[:user_id]
      @current_user = env['warden'].user if env['warden'].authenticated?
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
  
  get '/' do
    # url = "http://geoip.elib.ru/cgi-bin/getdata.pl"
    # resp = Net::HTTP.get_response(URI.parse(url))
    # city = Nokogiri::Slop(resp.body).GeoIP.GeoAddr.Town.content
    # url = URI::encode("http://api.vk.com/method/database.getCities?v=5&country_id=1&count=1&q="+city)
    # resp = Net::HTTP.get_response(URI.parse(url))
    # puts "*******", JSON.parse(resp.body), "*******"
    @activelink = '/'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:status => 0, :offset => @offset, :limit => 10, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
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
      if !session[:siteregionplaceholder]
        session[:siteregionplaceholder] = "Россия"
      end 
      haml :navbarbeforelogin do
        haml :index, :layout => :promo
      end
    else
      haml :navbarafterlogin do
        haml :index
      end
    end
  end

  post '/' do
    #@activelink = '/'
    #if params[:page].nil?
    #  @offset = 0
    #  @current_page = 1
    #else
    #  @offset = params[:page].to_i*10
    #  @current_page = params[:page].to_i
    #end
    #@orders_at_mainpage = Order.all(:status => 0, :offset => @offset, :limit => 10, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
    #@orders_at_mainpage_total = @orders_at_mainpage.count
    #@total_pages = (@orders_at_mainpage_total/10.0).ceil
    #@start_page = (@current_page - 5) > 0 ? (@current_page - 5) : 1
    #@end_page = @start_page + 10
    #if @end_page > @total_pages
    #  @end_page = @total_pages
    #  @start_page = (@end_page - 10) > 0 ? (@end_page - 10) : 1
    #end
    #@pagination = @start_page..@end_page
    session[:siteregion] = params[:siteregion]
    session[:sitearea] = params[:sitearea]
    session[:sitelocation] = params[:sitelocation]
    session[:siteregionplaceholder] = params[:sitelocation] + (params[:sitearea].size > 0 ? ", " + params[:sitearea] : "") + (params[:siteregion].size > 0 ? ", " + params[:siteregion] : "")
    #if !logged_in?
    #  haml :navbarbeforelogin do
    #    haml :index, :layout => :promo
    #  end
    #else
    #  haml :navbarafterlogin do
    #    haml :index
    #  end
    #end
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

  get '/region/:region' do
    @activelink = '/region'
    if params[:page].nil?
      @offset = 0
      @current_page = 1
    else
      @offset = params[:page].to_i*10
      @current_page = params[:page].to_i
    end
    @orders_at_mainpage = Order.all(:placement => {:region => params[:region]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
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
    @orders_at_mainpage = Order.all(:placement => {:area => params[:area]}, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
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
      session[:messagetodisplay] = "Ошибка при повторном вводе пароля. Пожалуйста, пройдите процедуру регистрации еще раз"
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
      user = User.new(
        :email => params[:email],
        :type => "User",
        :fullname => h(params[:fullname]),
        :created_at => DateTime.now,
        :password => params[:password],
        :placement => placement,
        :status => 0,
        :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
      begin
        user.save
        session[:user_id] = user.id
        @msg = "Здравствуйте, " + user.displayedname + "!\nВы успешно зарегистрировались на сайте РемЗона24.ру" + "\n\nДля входа на сайт используйте Ваш логин (" + user.email + ") и пароль, указанный при регистрации.\n\nЭто уведомление создано и отправлено автоматически, отвечать на него не нужно.\n\n--\nС уважением, РемЗона24.ру"
        Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
        env['warden'].authenticate!
        redirect '/profile'
      rescue
        session[:messagetodisplay] = user.errors.values.join("; ")
        redirect back
      end
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
  end

  post '/regmaster' do
    if params[:password] != params[:pass]
      session[:messagetodisplay] = "Ошибка при повторном вводе пароля. Пожалуйста, пройдите процедуру регистрации еще раз"
      redirect back
    end
    placement = Placement.first_or_new(
      :region => params[:region],
      :area => params[:area],
      :location => params[:locationtitle])
    begin
      placement.save
      user = User.new(
        :email => params[:email],
        :type => "Master",
        :familyname => Unicode::capitalize(h(params[:familyname])),
        :name => Unicode::capitalize(h(params[:name])),
        :fathersname => Unicode::capitalize(h(params[:fathersname])),
        :created_at => DateTime.now,
        :password => params[:password],
        :placement => placement,
        :status => 0,
        :profile => Profile.new(:showemail => true, :showphone => true, :sendmessagestoemail => true))
      begin
        user.save
        session[:user_id] = user.id
        @msg = "Здравствуйте, " + user.displayedname + "!\nВы успешно зарегистрировались на сайте РемЗона24.ру" + "\n\nДля входа на сайт используйте Ваш логин (" + user.email + ") и пароль, указанный при регистрации.\n\nЭто уведомление создано и отправлено автоматически, отвечать на него не нужно.\n\n--\nС уважением, РемЗона24.ру"
        Pony.mail(:to => user.email, :subject => 'Регистрация на РемЗона24.ру', :body => @msg)
        env['warden'].authenticate!
        redirect '/profile'
      rescue
        session[:messagetodisplay] = user.errors.values.join("; ")
        redirect back
      end
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
  end

  get '/profile' do
    if logged_in?
      @messages = Message.all(:receiver => current_user, :sender.not => current_user, :archived => false, :order => [ :date.desc ])
      @archivedmessages = Message.all(:receiver => current_user, :sender.not => current_user, :archived => true, :order => [ :date.desc ])      
      @newmessages = Message.count(:receiver => current_user, :sender.not => current_user, :unread => true)
      haml :navbarafterlogin do
        case @current_user.type
          when "User"
            @myactiveorders = Order.all(:user => current_user, :status => 0, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd = td'], :order => [ :fd.desc ]) | Order.all(:td.gte => DateTime.now, :order => [ :fd.desc ]))
            @myclosedorders = Order.all(:user => current_user, :status => 1, :order => [ :fd.desc ]) & (Order.all(:conditions => ['fd <> td'], :td.lt => DateTime.now, :order => [ :fd.desc ]))
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
            haml :masterprofile
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
        session[:messagetodisplay] = "Пользователь не найден"
        redirect back
      ensure
        if @user.nil?
          session[:messagetodisplay] = "Пользователь не найден"
          redirect back
        end
      end
      if logged_in?
        haml :navbarafterlogin do
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
        session[:messagetodisplay] = "Для просмотра подробной информации об участнике Портала, пожалуйста, войдите в систему"
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
          @current_user.update(:name => h(params[:name]), :fathersname => h(params[:fathersname]), :familyname => h(params[:familyname]), :description => h(params[:description]), :phone => h(params[:phone]), :email => h(params[:email]), :placement => placement)
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
          @current_user.update(:avatar => params[:avatar], :fullname => h(params[:fullname]), :email => h(params[:email]), :placement => placement)
        rescue
          session[:messagetodisplay] = @current_user.errors.values.join("; ")
          redirect back
        end
      end
    rescue
      session[:messagetodisplay] = placement.errors.values.join("; ")
      redirect back
    end
    session[:messagetodisplay] = "Профиль был успено обновлен"
    redirect back
  end

  post '/changepassword' do
    if logged_in?
      if @current_user.password != params[:oldpass]
        session[:messagetodisplay] = "Неправильно указан старый пароль. Пожалуйста, попробуйте сменить пароль еще раз"
        redirect back
      end
      if params[:newpass1] != params[:newpass2]
        session[:messagetodisplay] = "Ошибка при повторном вводе нового пароля. Пожалуйста, попробуйте сменить пароль еще раз"
        redirect back
      end
      @current_user.update(:password => params[:newpass1])
      haml :navbarafterlogin do
        haml :profile
      end
    else
      redirect back
    end
  end
  
  post '/resetpass' do
    user = User.first(:email=>params[:email])
    if !user
      session[:messagetodisplay] = "Указанный адрес электронной почты не зарегистрирован на Портале"
      redirect back
    else
      begin
        resetrequest = ResetPasswords.first_or_new({:email => user.email}, {:td => DateTime.now+1, :myhash => (user.email + DateTime.now.to_s)})
        resetrequest.save
        session[:messagetodisplay] = "Ваш запрос был получен. Проверьте почту для сброса пароля"
        @msg = "Здравствуйте!\nКто-то (возможно вы) запросил сброс пароля на сайте РемЗона24.ру\n\nДля сброса пароля перейдите по ссылке http://" + request.host + ":" + request.port.to_s + "/resetpass?reset=" + resetrequest.myhash + "\nДанная ссылка будет действительна в течении 24-х часов или до факта сброса пароля.\n\nЭто уведомление создано и отправлено автоматически, отвечать на него не нужно.\n\n--\nС уважением, РемЗона24.ру"
        Pony.mail(:to => user.email, :subject => 'Сброс пароля на РемЗона24.ру', :body => @msg)
        redirect back
      rescue
        session[:messagetodisplay] = "При сбросе пароля произошла ошибка. Попробуйте еще раз "
        session[:messagetodisplay] += resetrequest.errors.values.join("; ")
        redirect back
      end
    end
  end

  get '/resetpass' do
    resetrequest = ResetPasswords.first(:myhash => params[:reset])
    if !resetrequest 
      session[:messagetodisplay] = "К сожалению, мы не можем сбросить пароль, т.к. заявки на сброс пароля не существует"
      redirect back
    elsif resetrequest.td < DateTime.now
      resetrequest.destroy
      session[:messagetodisplay] = "К сожалению, мы не можем сбросить пароль, т.к. заявка на сброс пароля просрочена"
      redirect back
    end
    if !logged_in?
      haml :navbarbeforelogin do
        resetrequest.update(:myhash => DateTime.now.to_s)
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
      session[:messagetodisplay] = "К сожалению, мы не можем сбросить пароль, т.к. заявки на сброс пароля не существует"
      redirect back
    else
      if params[:newpass1] != params[:newpass2]
        session[:messagetodisplay] = "Ошибка при повторном вводе нового пароля. Пожалуйста, попробуйте сменить пароль еще раз"
      else
        user = User.first(:email => resetrequest.email)
        user.update(:password => params[:newpass1])
        session[:messagetodisplay] = "Пароль успешно был изменен"
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
    session[:messagetodisplay] = "Настройки были успешно обновлены"
    redirect back
  end  

  get '/regsuccess' do
    if logged_in?
      haml :navbarafterlogin do
        haml :regsuccess
      end
    else
      session[:messagetodisplay] = "К сожалению, при входе в систему возникла ошибка. Пожалуйста, попробуйте войти еще раз"
      redirect back
    end
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
      budget = params[:budget]
    end
    
    order = Order.new(
      :user => current_user,
      :title => h(params[:title]),
      :subject => h(params[:subject]),
      :budget => budget,
      :fd => fd,
      :td => td,
      :status => 0,
      :views => 0,
      :placement => @current_user.placement)
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
    if !params[:photos].nil?
      params[:photos].each do |image|
        oi = Orderimage.create(:order => order, :image => image)
      end
    end
    session[:messagetodisplay] = "Заявка успешно создана!"
    redirect '/'
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
    int_msg = "Здравствуйте! <br/> По вашей <a href='http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + "'>заявке</a> было размещено новое предложение. Ознакомиться с ним вы можете по этой <a href='http://" + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "'>ссылке</a>.</br>--<br/>С уважением, РемЗона24.ру"
    message = Message.new(
      :sender => User.get(1),
      :receiver => order.user,
      :type => "Offer",
      :date => DateTime.now,
      :text => int_msg,
      :order => order,
      :unread => true,
      :type => "Offer")
    begin
      message.save
    rescue
      session[:messagetodisplay] += message.errors.values.join("; ")
      redirect back
    end
    email_msg = "Здравствуйте!\nПо вашей заявке (http://" + request.host + ":" + request.port.to_s + "/order/" + order.id.to_s + ") было размещено новое предложение. Ознакомиться с ним вы можете по этой ссылке: http://" + request.host + ":" + request.port.to_s + "/offer/" + offer.id.to_s + "\n--\nС уважением, РемЗона24.ру"
    if get_settings(order.user, "sendmessagestoemail")
      Pony.mail(:to => order.user.email, :subject => 'Вы получили новое предложение на РемЗона24.ру', :body => email_msg)
    end
    session[:messagetodisplay] = "Ваше предложение принято. Соответствующее уведомление было отправлено заказчику"
    redirect back
  end

  post '/addquestionto' do
    #current_user
    if params.has_key?("order")
      @order = Order.get(params[:order])
      @message = Message.new(
        :sender => current_user,
        :receiver => @order.user,
        :order => @order,
        :unread => true,
        :text => h(params[:question]),
        :date => DateTime.now,
        :type => "Question"
      )
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
      ensure
        redirect back
      end
    end
    if params.has_key?("offer")
      @offer = Order.get(params[:offer])
      @message = Message.new(
        :sender => current_user,
        :receiver => @offer.user,
        :offer => @offer,
        :unread => true,
        :text => h(params[:question]),
        :date => DateTime.now,
        :type => "Question"
      )
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
      ensure
        redirect back
      end
    end
  end

  get '/order/:order' do
    begin
      @order = Order.get(params[:order].to_i)
    rescue
      session[:messagetodisplay] = "Заявка не существует"
      redirect '/profile'
    ensure
      if @order.nil? || @order.status == 2
        session[:messagetodisplay] = "Заявка не существует"
        redirect '/profile'
      end  
    end
    @tags = []
    @order.tags.all.each do |t|
      @tags << t.tag
    end
    @tags = @tags.join(', ')
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

    @questionsnumber = Message.count(:order_id => params[:order].to_i, :type => "Question")

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
      session[:messagetodisplay] = "Заявка не существует"
      redirect back
    ensure
      if @order.nil?
        session[:messagetodisplay] = "Заявка не существует"
        redirect back
      end
    end
    if !logged_in?
      haml :navbarbeforelogin do
        session[:messagetodisplay] = "Для просмотра комментариев к заявке, пожалуйста, войдите в систему"
        redirect back
      end
    else
      #@offer = Offer.get(@order.offer_id)
      @questions = Message.all(:order_id => params[:order].to_i, :type => "Question")
      
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
          session[:messagetodisplay] = "Заявка была перенесена в архив"
          redirect back
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
          session[:messagetodisplay] = "Вы не можете удалить заявку"
          redirect back
        else
          order.update(:status => 2, :td => DateTime.now)
          session[:messagetodisplay] = "Заявка была удалена"
          redirect back
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
      session[:messagetodisplay] = "Предложения не существует"
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = "Предложения не существует"
        redirect back
      end  
    end
    if !logged_in?
      session[:messagetodisplay] = "Для просмотра предложения, пожалуйста, войдите в систему"
      redirect back
    else
      haml :navbarafterlogin do
        @order = Order.get(@offer.order_id)
        @questionsnumber = Message.count(:offer_id => params[:id].to_i, :type => "Question")
        haml :offerdetails
      end
    end
  end
  
  get '/offer/:offer/comments' do
    begin
      @offer = Offer.get(params[:offer].to_i)
    rescue
      session[:messagetodisplay] = "Предложение не существует"
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = "Предложение не существует"
        redirect back
      end
    end
    if !logged_in?
      session[:messagetodisplay] = "Для просмотра комментариев к предложению, пожалуйста, войдите в систему"
      redirect back
    else
      @order = Order.get(@offer.order_id)
      @questions = Message.all(:offer_id => params[:offer].to_i, :type => "Question")
      
      haml :navbarafterlogin do
        haml :offercomments
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
        offer = Ofer.get(params[:offer].to_i)
        if offer.user != current_user
          session[:messagetodisplay] = "Вы не можете снять предложение"
          redirect back
        else
          offer.update(:status => 1, :td => DateTime.now)
          session[:messagetodisplay] = "Предложение было отменено и перенесено в архив"
          redirect back
        end
      end
    end
  end
  
  post '/offer/:offer/startwork' do
    begin
      @offer = Offer.get(params[:offer].to_i)
      if @offer.status != 0
        session[:messagetodisplay] = "Предложения не существует"
        redirect back
      end
    rescue
      session[:messagetodisplay] = "Предложения не существует"
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = "Предложения не существует"
        redirect back
      end  
    end
    if !logged_in? || Order.get(@offer.order).user != current_user
      redirect '/'
    else
      if @offer.status != 0
        session[:messagetodisplay] = "Предложение не действительно"
        redirect back
      end
      #@contract = Contract.new(:customer => current_user, :contractor => @offer.user)
      #begin
      #  @contract.save
      @offer.update(:status => 2)
      
      int_msg = "Здравствуйте!<br/>Ваше предложение было принято. Пожалуйста, <a href='http://" + request.host + ":" + request.port.to_s + "/offer/" + @offer.id.to_s +  "'>подтвердите</a> свою готовность выполнить работу."
      if params[:message] && params[:message].size>0
        int_msg += "<br/>Дополнительная информация от заказчика:<br/>" + params[:message]
      end
      int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
      @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @offer.user, :type => "Request")
      begin
        @message.save
      rescue
        session[:messagetodisplay] = @message.errors.values.join("; ")
        redirect back
      end
      email_msg = "Здравствуйте!\nВаше предложение было принято. Пожалуйста, подтвердите свою готовность выполнить работу по этой ссылке: http://" + request.host + ":" + request.port.to_s + "/offer/" + @offer.id.to_s
      if params[:message] && params[:message].size>0
        email_msg += "\nДополнительная информация от заказчика:\n" + params[:message]
      end
      email_msg += "\n--\nС уважением, РемЗона24.ру"
      if get_settings(@offer.user, "sendmessagestoemail")
        Pony.mail(:to => @offer.user.email, :subject => 'Ваше предложение было принято на РемЗона24.ру', :body => email_msg)
      end
      session[:messagetodisplay] = "Вы приняли предложение. Соответствующее уведомление было отправлено исполнителю"
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
      session[:messagetodisplay] = "Предложения не существует"
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = "Предложения не существует"
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
      @contract = Contract.new(:customer => @order.user, :contractor => current_user)
      begin
        @contract.save
        @offer.update(:status => 3)
        
        int_msg = "Здравствуйте!<br/>Предложение было подтверждено исполнителем."
        int_msg += "<br/>--<br/>С уважением, РемЗона24.ру"
        @message = Message.new(:unread => true, :date => DateTime.now, :text => int_msg, :sender => User.get(1), :receiver => @order.user, :type => "Accept")
        begin
          @message.save
        rescue
          session[:messagetodisplay] = @message.errors.values.join("; ")
          redirect back
        end
        email_msg = "Здравствуйте!\nПредложение было принято."
        email_msg += "\n--\nС уважением, РемЗона24.ру"
        if get_settings(@order.user, "sendmessagestoemail")
          Pony.mail(:to => @order.user.email, :subject => 'Потверждение начала работ на РемЗона24.ру', :body => email_msg)
        end
        session[:messagetodisplay] = "Вы подтвердили готовность выполнить работы. Соответствующее уведомление было отправлено заказчику."
        redirect 'profile'
      rescue
        session[:messagetodisplay] = @contract.errors.values.join("; ")
        redirect back
      end
    end
  end

  post '/offer/:offer/refusereason' do
    begin
      @offer = Offer.get(params[:offer].to_i)
      #if @offer.status != 0
      #  session[:messagetodisplay] = "Предложения не существует"
      #  redirect back
      #end
    rescue
      session[:messagetodisplay] = "Предложения не существует"
      redirect back
    ensure
      if @offer.nil?
        session[:messagetodisplay] = "Предложения не существует"
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
      @order = Order.get(@offer.order)
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
        session[:messagetodisplay] = "Сообщение не найдено"
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = "Вы не можете прочитать это сообщение"
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
        session[:messagetodisplay] = "Сообщение не найдено"
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = "Вы не можете поместить это сообщение в архив"
        redirect back
      end
      @msg.update(:archived => true)
      session[:messagetodisplay] = "Сообщение было помещенно в архив"
    end
    redirect '/profile'
  end

  delete '/message/:id' do
    if !logged_in?
      redirect '/'
    else
      @msg = Message.get(params[:id].to_i)
      if !@msg
        session[:messagetodisplay] = "Сообщение не найдено"
        redirect back
      end
      if @msg.receiver != current_user
        session[:messagetodisplay] = "Вы не можете удалить это сообщение"
        redirect back
      end
      @msg.destroy
      session[:messagetodisplay] = "Сообщение было удалено"
    end
    redirect '/profile'
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
      session[:user_id] = nil
      session[:messagetodisplay] = "Вы вышли из системы"
      redirect '/'
    end
  end

end

Remzona24App.run!