import Foundation

class DirectFetcher {
    func fetchData(completion: @escaping (String) -> Void) {
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items"
        guard let url = URL(string: urlString) else {
            completion("Ugyldig URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer 81734a0b8bd3e2352d9325258ad958eea1626c447113661c97d13b5d3b12efa1", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion("Netværksfejl:\n\(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    completion("Ingen data modtaget.")
                    return
                }
                if let jsonString = String(data: data, encoding: .utf8) {
                    completion(jsonString)
                } else {
                    completion("Kunne ikke konvertere data til tekst.")
                }
            }
        }.resume()
    }
} 