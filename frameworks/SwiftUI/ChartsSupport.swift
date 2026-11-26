// For Charts (frameworks/Charts): a ForEach whose content is chart
// content, not a view. Apple's Charts builds ForEach<Data, ID, Content>
// with Content: ChartContent through inits SwiftUI keeps internal.

extension ForEach {
  public init(_chartData data: Data, id: @escaping (Data.Element) -> ID, content: @escaping (Data.Element) -> Content) {
    self.init(data: data, id: id, content: content)
  }
}
