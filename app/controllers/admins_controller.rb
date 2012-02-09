require File.join(Rails.root, 'lib','statistics')

class AdminsController < ApplicationController
  before_filter :authenticate_user!
  before_filter :redirect_unless_admin

  def user_search
    params[:user] ||= {}
    params[:user].delete_if {|key, value| value.blank? }
    @users = params[:user].empty? ? [] : User.where(params[:user])
  end

  def admin_inviter 
    email = params[:idenitifer]
    user = User.find_by_email(email)
    
    unless user
      EmailInviter.new(email).send!
      flash[:notice] = "invitation sent to #{email}"
    else
      flash[:notice]= "error sending invite to #{email}"
    end
    redirect_to user_search_path, :notice => flash[:notice]
  end

  def weekly_user_stats
    @created_users_by_day = User.where("username IS NOT NULL").count(:group => "date(created_at)") 
    @created_users_by_week = {}
    @created_users_by_day.keys.each do |k| 
      unless k.nil?
        if @created_users_by_week[k.beginning_of_week].blank?
          @created_users_by_week[k.beginning_of_week] = @created_users_by_day[k] 
        else
          @created_users_by_week[k.beginning_of_week] += @created_users_by_day[k] 
        end
      end
    end
  end

  def stats
    @popular_tags = ActsAsTaggableOn::Tagging.joins(:tag).limit(15).count(:group => :tag, :order => 'count(taggings.id) DESC')

    case params[:range]
    when "week"
      range = 1.week
      @segment = "week"
    when "2weeks"
      range = 2.weeks
      @segment = "2 week"
    when "month"
      range = 1.month
      @segment = "month"
    else
      range = 1.day
      @segment = "daily"
    end

    [Post, Comment, AspectMembership, User].each do |model|
      create_hash(model, :range => range)
    end

    @posts_per_day = Post.count(:group => "DATE(created_at)", :conditions => ["created_at >= ?", Date.today - 21.days], :order => "DATE(created_at) ASC")
    @most_posts_within = @posts_per_day.values.max.to_f

    @user_count = User.count

    #@posts[:new_public] = Post.where(:type => ['StatusMessage','ActivityStreams::Photo'],
    #                                 :public => true).order('created_at DESC').limit(15).all

  end

  def correlations
    @correlations_hash = Statistics.new.generate_correlations
  end

  private
  def percent_change(today, yesterday)
    sprintf( "%0.02f", ((today-yesterday) / yesterday.to_f)*100).to_f
  end

  def create_hash(model, opts={})
    opts[:range] ||= 1.day
    plural = model.to_s.underscore.pluralize
    eval(<<DATA
      @#{plural} = {
        :day_before => #{model}.where(:created_at => ((Time.now.midnight - #{opts[:range]*2})..Time.now.midnight - #{opts[:range]})).count,
        :yesterday => #{model}.where(:created_at => ((Time.now.midnight - #{opts[:range]})..Time.now.midnight)).count
      }
      @#{plural}[:change] = percent_change(@#{plural}[:yesterday], @#{plural}[:day_before])
DATA
    )
  end
end
