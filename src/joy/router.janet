(import ./helper :prefix "")
(import ./http :as http)

(varglobal '*route-table* @{})

(defn- route-param [val]
  (if (and (string? val)
        (string/has-prefix? ":" val))
    val
    (string ":" val)))


(defn- route-url [string-route struct-params]
  (var mut-string-route string-route)
  (loop [[k v] :in (pairs struct-params)]
    (set mut-string-route (string/replace (route-param k) (string v) mut-string-route)))
  mut-string-route)


(defn- route-matches? [array-route1 dictionary-request]
  (let [[route-method route-url] array-route1
        {:method method :uri uri} dictionary-request
        url (first (string/split "?" uri))]
    (true? (and (= (string/ascii-lower method) (string/ascii-lower route-method))
             (= route-url url)))))


(defn- route-params [string-route-url string-request-url]
  (if (true?
       (and (string? string-route-url)
         (string? string-request-url)))
    (let [route-url-segments (string/split "/" string-route-url)
          request-url-segments (string/split "/" string-request-url)]
      (if (= (length route-url-segments)
            (length request-url-segments))
        (as-> (interleave route-url-segments request-url-segments) %
              (apply struct %)
              (select-keys % (filter (fn [x] (string/has-prefix? ":" x)) route-url-segments))
              (map-keys (fn [val] (-> (string/replace ":" "" val) (keyword))) %))
        {}))
    {}))


(defn- find-route [indexed-routes dictionary-request]
  (let [{:uri uri :method method} dictionary-request]
    (or (get
          (filter (fn [indexed-route]
                    (let [[method url handler] indexed-route
                          url (route-url url
                                (route-params url uri))
                          indexed-route [method url handler]]
                      (route-matches? indexed-route dictionary-request)))
            indexed-routes) 0)
        [])))


(defn- route-name [route]
  (-> route last keyword))


(defn- route-table [routes]
  (->> routes
       (mapcat |(tuple (route-name $) $))
       (apply table)))


(defn handler
  "Creates a handler function from routes. Returns nil when handler/route doesn't exist."
  [routes]
  (fn [request]
    (let [{:uri uri} request
          route (find-route routes request)
          [route-method route-uri route-fn] route
          params (route-params route-uri uri)
          request (merge request {:params params})]
      (when (function? route-fn)
        (route-fn request)))))


(defn app [& handlers]
  (fn [request]
    (some |($ request) handlers)))


(defmacro routes [& args]
  (do
    ~(set *route-table* (merge *route-table* (route-table ,;args)))))


(defn present? [val]
  (and (truthy? val)
       (not (empty? val))))


(defn namespace [val]
  (when (keyword? val)
    (let [arr (string/split "/" val)
          len (dec (length arr))
          ns-array (array/slice arr 0 len)]
      (string/join ns-array "/"))))


(defmacro defroutes [& args]
  (let [name (first args)
        rest (drop 1 args)
        rest (map |(array ;$) rest)

        # get the "namespaces" of the functions
        files (as-> rest ?
                    (map |(get $ 2) ?)
                    (map namespace ?)
                    (filter present? ?)
                    (distinct ?))

        # import all distinct file names from routes
        _ (loop [file :in files]
            (try
              (import* (string "./routes/" file) :as file)
              ([err]
               (print (string "Route file src/routes/" file ".janet does not exist.")))))

        rest (map |(update $ 2 symbol) rest)]

    (routes rest)
    ~(def ,name :public ,rest)))


(defn- query-string [m]
  (when (dictionary? m)
    (let [s (->> (pairs m)
                 (map (fn [[k v]] (string (-> k string http/url-encode) "=" (http/url-encode v))))
                 (join-string "&"))]
      (when (not (empty? s))
        (string "?" s)))))


(defn url-for [route-keyword &opt params]
  (default params {})
  (let [route (get *route-table* route-keyword)
        _ (when (nil? route) (error (string "Route " route-keyword " does not exist")))
        route-params (->> (kvs params)
                          (apply table))
        route-params (-> (put route-params :? nil)
                         (put "#" nil))
        url (route-url (get route 1) route-params)
        query-params (get params :?)
        qs (or (query-string query-params) "")
        anchor (get params "#")
        anchor (if (not (nil? anchor)) (string "#" anchor) "")]
    (string url qs anchor)))


(defn action-for [route-keyword &opt params]
  (default params {})
  (let [[method url] (get *route-table* route-keyword)
        action (route-url url params)
        _method (when (not= :post method) method)
        method (if (not= :get method) :post :get)]
    {:method method
     :_method _method
     :action action}))


(defn redirect-to [route-keyword &opt params]
  @{:status 302
    :body " "
    :headers @{"Location" (url-for route-keyword (or params {}))}})
