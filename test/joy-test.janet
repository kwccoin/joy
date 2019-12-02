(import tester :prefix "" :exit true)
(import "src/joy" :prefix "")


(defn layout [response]
  (let [{:body body} response]
    (render :html
      (html
       (doctype :html5)
       [:html {:lang "en"}
        [:head
         [:meta {:charset "utf-8"}]
         [:meta {:name "viewport" :content "width=device-width, initial-scale=1"}]
         [:title "joy test 1"]]
        [:body body]]))))


(defn set-account [handler]
  (fn [request]
    (let [{:db db :params params} request
          id (get params :id)
          account (fetch db [:account id])]
      (handler
       (merge request {:account account :id id})))))


(def insert-params
  (params
    (validates [:name :email :password] :required true)
    (permit [:name :email :password])))


(def update-params
  (params
    (validates [:name :email] :required true)
    (permit [:name :email])))


(defn home [request]
  [:h1 {:style "text-align: center"} "You've found joy!"])


(defn index [request]
  (let [{:db db :session session} request
        accounts (fetch-all db [:account])]
    [:table
     [:thead
      [:tr
       [:th "id"]
       [:th "name"]
       [:th "email"]
       [:th "password"]
       [:th]
       (when (not (nil? session))
         [:th])]]
     [:tbody
      (map
       (fn [{:id id :name name :email email :password password}]
         [:tr
          [:td id]
          [:td name]
          [:td email]
          [:td password]
          [:td
           [:a {:href (url-for request :edit {:id id})}
            "Edit"]]
          (when (not (nil? session))
            [:td
             [:form (action-for request :destroy {:id id})
              [:input {:type "hidden" :name "_method" :value "delete"}]
              [:input {:type "submit" :value "Delete"}]]])])
       accounts)]]))


(defn show [request]
  (let [{:account account} request
        {:id id :name name :email email :password password :created_at created-at} account]
    [:table
     [:tr
      [:th "id"]
      [:th "name"]
      [:th "email"]
      [:th "password"]
      [:th "created_at"]]
     [:tr
      [:td id]
      [:td name]
      [:td email]
      [:td password]
      [:td created-at]]]))


(defn form [action &opt account]
  (default account {})
  (let [{:name name :email email :password password} account]
    [:form action
     [:input {:type "hidden" :name "_method" :value (or (get action :_method)
                                                      (get action :method))}]
     [:div
      [:label {:for "name"} "Name"]
      [:br]
      [:input {:type "text" :name "name" :value name}]]
     [:div
      [:label {:for "email"} "Email"]
      [:br]
      [:input {:type "email" :name "email" :value email}]]
     [:div
      [:label {:for "password"} "Password"]
      [:br]
      [:input {:type "password" :name "password" :value password}]]
     [:div
      [:input {:type "submit" :value "Create"}]]]))


(defn new [request]
  (form (action-for request :create)))


(defn create [request]
  (let [{:db db} request
        [errors account] (->> (insert-params request)
                              (insert db :account)
                              (rescue))]
    (if (nil? errors)
      (-> (redirect-to request :index)
          (put :session account))
      (new (put request :errors errors)))))


(defn edit [request]
  (let [{:account account} request
        action (action-for request :patch account)]
    (form action account)))


(defn patch [request]
  (let [{:db db :id id} request
        [errors account] (->> (update-params request)
                              (update db :account id)
                              (rescue))]
    (if (nil? errors)
      (redirect-to request :index)
      (edit (put request :errors errors)))))


(defn destroy [request]
  (let [{:db db :id id} request]
    (delete db :account id)
    (redirect-to request :index)))


(defn error-test [request]
  (error "test error"))


(def account-routes
  (routes
    [:get "/accounts" index]
    [:get "/accounts/new" new]
    [:post "/accounts" create]
    (middleware set-account
      [:get "/accounts/:id" show]
      [:get "/accounts/:id/edit" edit]
      [:patch "/accounts/:id" patch]
      [:delete "/accounts/:id" destroy])))


(def home-routes
  (routes
   [:get "/" home]
   [:get "/error-test" error-test]))


(def routes
  (routes
    home-routes
    account-routes))


(def app (-> (app routes)
             (set-db "test.sqlite3")
             (set-layout layout)
             (session)
             (static-files)
             (logger)
             (extra-methods)
             (query-string)
             (body-parser)
             (server-error)))


# (with-db-connection [conn "test.sqlite3"])
#   (execute conn "create table if not exists account (id integer primary key, name text not null unique, email text not null unique, password text not null, created_at integer not null default(strftime('%s', 'now')))")
#
# (serve app 8000)


(deftest
  (test "joy get env variable with a single keyword"
    (do
      (os/setenv "JOY_ENV" "development")
      (= "development" (env :joy-env))))

  (test "test everything"
    (= {:status 200 :headers {"Content-Type" "text/html; charset=utf-8"} :body `<!DOCTYPE HTML><html lang="en"><head><meta charset="utf-8" /><meta content="width=device-width, initial-scale=1" name="viewport" /><title>joy test 1</title></head><body><h1 style="text-align: center">You've found joy!</h1></body></html>`}
       (freeze
         (app @{:method :get :uri "/"})))))
